"""
Pokémon Diamond Capsule Seal Extractor - FINAL v12
Key fixes from v11:
- Cell rendering is PREFERRED over tiled rendering when valid OAMs exist
- For multi-cell NCERs (animation frames), pick the frame with best visual output
- For 2D mapped NCGRs, cell render uses ncgr_tile_w for proper VRAM addressing
- Tiled fallback only used when no valid cell data exists

Install: pip install ndspy Pillow
"""

import struct
import math
from pathlib import Path
from PIL import Image
import ndspy.lz10
from ndspy.graphics2D import loadImageTiles, ImageFormat

INPUT_FOLDER = "cb_data_extracted"
OUTPUT_FOLDER = "output"

OAM_SIZES = {
    (0, 0): (8, 8),   (0, 1): (16, 16), (0, 2): (32, 32), (0, 3): (64, 64),
    (1, 0): (16, 8),  (1, 1): (32, 8),  (1, 2): (32, 16), (1, 3): (64, 32),
    (2, 0): (8, 16),  (2, 1): (8, 32),  (2, 2): (16, 32), (2, 3): (32, 64),
}


def try_decompress(data):
    if len(data) >= 4 and data[0] == 0x10:
        try:
            return ndspy.lz10.decompress(data)
        except Exception:
            pass
    return data


def parse_nclr(data):
    if data[:4] not in (b'RLCN', b'NCLR'):
        return None
    for i in range(len(data) - 4):
        if data[i:i+4] in (b'PLTT', b'TTLP'):
            section_size = struct.unpack_from('<I', data, i + 4)[0]
            color_start = i + 24
            color_end = i + section_size
            colors = []
            for j in range(color_start, min(color_end, len(data) - 1), 2):
                val = struct.unpack_from('<H', data, j)[0]
                colors.append((val & 0x1F, (val >> 5) & 0x1F, (val >> 10) & 0x1F))
            return colors
    return None


def parse_ncgr(data):
    if data[:4] not in (b'RGCN', b'NCGR'):
        return None
    char_off = -1
    for i in range(len(data) - 4):
        if data[i:i+4] in (b'CHAR', b'RAHC'):
            char_off = i
            break
    if char_off == -1:
        return None
    tile_h = struct.unpack_from('<H', data, char_off + 0x08)[0]
    tile_w = struct.unpack_from('<H', data, char_off + 0x0A)[0]
    bpp_flag = struct.unpack_from('<I', data, char_off + 0x0C)[0]
    bpp = 4 if bpp_flag == 3 else 8
    mapping_type = struct.unpack_from('<I', data, char_off + 0x10)[0]
    tile_data_size = struct.unpack_from('<I', data, char_off + 0x18)[0]
    tile_start = char_off + 0x20
    tile_data = data[tile_start:tile_start + tile_data_size]
    bpt = 32 if bpp == 4 else 64
    usable = (len(tile_data) // bpt) * bpt
    tile_data = tile_data[:usable]
    if len(tile_data) < bpt:
        return None
    return tile_data, bpp, tile_w, tile_h, mapping_type


def parse_ncer(data):
    if data[:4] not in (b'RECN', b'NCER'):
        return None
    cebk_off = -1
    for i in range(len(data) - 4):
        if data[i:i+4] in (b'CEBK', b'KBEC'):
            cebk_off = i
            break
    if cebk_off == -1:
        return None

    num_cells = struct.unpack_from('<H', data, cebk_off + 0x08)[0]
    bank_type = struct.unpack_from('<H', data, cebk_off + 0x0A)[0]
    mapping_type = struct.unpack_from('<I', data, cebk_off + 0x10)[0]

    cell_entry_size = 16 if bank_type == 1 else 8
    cell_entries_start = cebk_off + 0x20
    oam_base = cell_entries_start + num_cells * cell_entry_size

    cells = []
    for c in range(num_cells):
        entry_off = cell_entries_start + c * cell_entry_size
        if entry_off + cell_entry_size > len(data):
            cells.append([])
            continue
        num_oam = struct.unpack_from('<H', data, entry_off)[0]
        oam_byte_offset = struct.unpack_from('<I', data, entry_off + 4)[0]

        if num_oam == 0 or num_oam > 128:
            cells.append([])
            continue
        if oam_byte_offset > 0x10000:
            cells.append([])
            continue

        oam_start = oam_base + oam_byte_offset
        cell_oams = []
        for o in range(num_oam):
            oam_off = oam_start + o * 6
            if oam_off + 6 > len(data):
                break
            attr0 = struct.unpack_from('<H', data, oam_off)[0]
            attr1 = struct.unpack_from('<H', data, oam_off + 2)[0]
            attr2 = struct.unpack_from('<H', data, oam_off + 4)[0]

            y = attr0 & 0xFF
            if y >= 128:
                y -= 256
            shape = (attr0 >> 14) & 3
            rs_flag = bool(attr0 & 0x100)
            disable = bool(attr0 & 0x200)
            if not rs_flag and disable:
                continue

            x = attr1 & 0x1FF
            if x >= 256:
                x -= 512
            hflip = bool(attr1 & 0x1000) if not rs_flag else False
            vflip = bool(attr1 & 0x2000) if not rs_flag else False
            size_bits = (attr1 >> 14) & 3

            tile_idx = attr2 & 0x3FF
            palette = (attr2 >> 12) & 0xF

            w, h = OAM_SIZES.get((shape, size_bits), (8, 8))
            cell_oams.append({
                'x': x, 'y': y, 'w': w, 'h': h,
                'tile': tile_idx, 'hflip': hflip, 'vflip': vflip,
                'palette': palette,
            })
        cells.append(cell_oams)
    return cells, mapping_type


def color5to8(c5):
    return (c5 << 3) | (c5 >> 2)


def render_cell(cell_oams, tiles, colors, bpp, tile_offset=0, ncgr_tile_w=0):
    if not cell_oams:
        return None
    min_x = min(o['x'] for o in cell_oams)
    min_y = min(o['y'] for o in cell_oams)
    max_x = max(o['x'] + o['w'] for o in cell_oams)
    max_y = max(o['y'] + o['h'] for o in cell_oams)
    img_w = max_x - min_x
    img_h = max_y - min_y
    if img_w <= 0 or img_h <= 0 or img_w > 512 or img_h > 512:
        return None
    img = Image.new('RGBA', (img_w, img_h), (0, 0, 0, 0))
    pal_size = 16 if bpp == 4 else 256

    for oam in cell_oams:
        ox = oam['x'] - min_x
        oy = oam['y'] - min_y
        tw = oam['w'] // 8
        th = oam['h'] // 8
        base_tile = oam['tile'] + tile_offset

        for ty in range(th):
            for tx in range(tw):
                if ncgr_tile_w > 0:
                    base_col = base_tile % ncgr_tile_w
                    base_row = base_tile // ncgr_tile_w
                    tile_num = (base_row + ty) * ncgr_tile_w + (base_col + tx)
                else:
                    tile_num = base_tile + ty * tw + tx

                if tile_num < 0 or tile_num >= len(tiles):
                    continue
                tile = tiles[tile_num]
                pal_offset = oam['palette'] * pal_size
                for py in range(8):
                    for px in range(8):
                        val = tile.pixels[py * 8 + px]
                        if val == 0:
                            continue
                        ci = pal_offset + val
                        if ci >= len(colors):
                            continue
                        r5, g5, b5 = colors[ci]
                        if oam['hflip']:
                            fx = (tw * 8 - 1) - (tx * 8 + px)
                        else:
                            fx = tx * 8 + px
                        if oam['vflip']:
                            fy = (th * 8 - 1) - (ty * 8 + py)
                        else:
                            fy = ty * 8 + py
                        dx = ox + fx
                        dy = oy + fy
                        if 0 <= dx < img_w and 0 <= dy < img_h:
                            img.putpixel((dx, dy),
                                         (color5to8(r5), color5to8(g5), color5to8(b5), 255))
    return img


def render_tiled(tiles, colors, bpp, tile_w, tile_h):
    n = len(tiles)
    if tile_w <= 0 or tile_h <= 0:
        return None
    if tile_w * tile_h < n:
        tile_h = math.ceil(n / tile_w)
    img = Image.new('RGBA', (tile_w * 8, tile_h * 8), (0, 0, 0, 0))
    for i, tile in enumerate(tiles):
        if i >= tile_w * tile_h:
            break
        bx = (i % tile_w) * 8
        by = (i // tile_w) * 8
        for py in range(8):
            for px in range(8):
                val = tile.pixels[py * 8 + px]
                if val == 0 or val >= len(colors):
                    continue
                r5, g5, b5 = colors[val]
                img.putpixel((bx + px, by + py),
                             (color5to8(r5), color5to8(g5), color5to8(b5), 255))
    return img


def count_visible(img):
    if img is None:
        return 0
    return sum(1 for px in img.getdata() if len(px) >= 4 and px[3] > 0)


def try_all_palettes(pal_list, render_fn):
    best_img = None
    best_score = 0
    best_pal = 0
    for pal_idx, colors in pal_list:
        padded = colors + [(0, 0, 0)] * max(0, 256 - len(colors))
        try:
            img = render_fn(padded)
            if img is None:
                continue
            bbox = img.getbbox()
            if bbox is None:
                continue
            cropped = img.crop(bbox)
            score = count_visible(cropped)
            if score > best_score:
                best_score = score
                best_img = cropped
                best_pal = pal_idx
        except Exception:
            pass
    return best_img, best_score, best_pal


def main():
    input_path = Path(INPUT_FOLDER)
    output_path = Path(OUTPUT_FOLDER)
    output_path.mkdir(exist_ok=True)

    if not input_path.exists():
        print(f"ERROR: Folder '{INPUT_FOLDER}' not found!")
        return

    all_files = sorted(
        input_path.iterdir(),
        key=lambda f: int(''.join(filter(str.isdigit, f.stem)) or 0)
    )

    print("Loading files...\n")
    file_data = {}
    file_types = {}
    for f in all_files:
        idx = int(''.join(filter(str.isdigit, f.stem)) or 0)
        raw = f.read_bytes()
        dec = try_decompress(raw) if f.suffix.lower() == '.bin' else raw
        file_data[idx] = dec
        magic = dec[:4]
        if magic in (b'RNAN', b'NANR'):    file_types[idx] = 'NANR'
        elif magic in (b'RECN', b'NCER'):  file_types[idx] = 'NCER'
        elif magic in (b'RGCN', b'NCGR'):  file_types[idx] = 'NCGR'
        elif magic in (b'RLCN', b'NCLR'):  file_types[idx] = 'NCLR'
        elif magic in (b'RCSN', b'NSCR'):  file_types[idx] = 'NSCR'
        else:                              file_types[idx] = 'unknown'

    palettes = {}
    for idx, typ in file_types.items():
        if typ == 'NCLR':
            colors = parse_nclr(file_data[idx])
            if colors:
                palettes[idx] = colors

    pal_list = sorted(palettes.items())
    print(f"Palettes: {len(pal_list)}\n")

    shared_ncer = None
    if 92 in file_data and file_types.get(92) == 'NCER':
        result = parse_ncer(file_data[92])
        if result:
            shared_ncer, _ = result

    if shared_ncer:
        print(f"  Shared NCER: {len(shared_ncer)} cells")
        for ci, cell in enumerate(shared_ncer):
            if cell:
                print(f"    Cell {ci}: {len(cell)} OAMs")
                for oam in cell[:5]:
                    print(f"      x={oam['x']:4d} y={oam['y']:4d} "
                          f"{oam['w']}x{oam['h']} tile={oam['tile']} pal={oam['palette']}")
    print()

    print("=== Rendering 92 seals ===\n")
    converted = 0
    skipped = 0

    for seal in range(92):
        ncer_idx = seal + 92
        ncgr_idx = seal + 184

        ncgr_result = parse_ncgr(file_data.get(ncgr_idx, b''))
        if ncgr_result is None:
            continue

        tile_data, bpp, ncgr_tw, ncgr_th, ncgr_mapping = ncgr_result
        fmt = ImageFormat.I4 if bpp == 4 else ImageFormat.I8
        tiles = loadImageTiles(tile_data, fmt)
        if not tiles:
            continue

        nonzero = sum(1 for b in tile_data if b != 0)
        if nonzero == 0:
            skipped += 1
            print(f"  Seal {seal:2d}: SKIP (blank)")
            continue

        n_tiles = len(tiles)
        cells = None
        ncer_mapping = 0
        if ncer_idx in file_data and file_types.get(ncer_idx) == 'NCER':
            result = parse_ncer(file_data[ncer_idx])
            if result:
                cells, ncer_mapping = result

        has_valid_ncgr_dims = (0 < ncgr_tw < 0xFFFF and 0 < ncgr_th < 0xFFFF)
        use_2d = has_valid_ncgr_dims and ncgr_mapping == 0
        vram_w = ncgr_tw if use_2d else 0

        non_empty_cells = [c for c in cells if c] if cells else []
        has_cells = len(non_empty_cells) > 0

        if seal >= 81:
            mapping_mode = "2D" if use_2d else "1D"
            print(f"    DEBUG seal {seal}: {n_tiles} tiles, NCGR={ncgr_tw}x{ncgr_th}, "
                  f"map={ncgr_mapping}, {mapping_mode}, {len(non_empty_cells)} non-empty cells")

        if has_cells:
            best_img = None
            best_score = 0
            best_pal = 0
            best_label = ''

            for cell_idx, cell_oams in enumerate(non_empty_cells):
                def make_render_fn(cell_oams_inner, vram_w_inner):
                    def fn(colors_):
                        return render_cell(cell_oams_inner, tiles, colors_, bpp,
                                           tile_offset=0, ncgr_tile_w=vram_w_inner)
                    return fn

                img, score, pal = try_all_palettes(
                    pal_list, make_render_fn(cell_oams, vram_w))
                if score > best_score:
                    best_score = score
                    best_img = img
                    best_pal = pal
                    best_label = f'cell_c{cell_idx}'

            if best_img:
                out_path = output_path / f'seal_{seal:03d}.png'
                best_img.save(str(out_path))
                converted += 1
                w, h = best_img.size
                print(f'  Seal {seal:2d}: SAVED seal_{seal:03d}.png '
                      f'({w}x{h}, {best_label}, pal={best_pal}, px={best_score})')
            else:
                skipped += 1
                print(f'  Seal {seal:2d}: SKIP (no valid render)')
        else:
            # Tiled fallback
            if not use_2d or ncgr_tw <= 0:
                cols = math.ceil(math.sqrt(n_tiles))
                rows = math.ceil(n_tiles / cols)
            else:
                cols = ncgr_tw
                rows = ncgr_th if ncgr_th > 0 else math.ceil(n_tiles / cols)

            def make_tiled_fn(cols_inner, rows_inner):
                def fn(colors_):
                    return render_tiled(tiles, colors_, bpp, cols_inner, rows_inner)
                return fn

            best_img, best_score, best_pal = try_all_palettes(
                pal_list, make_tiled_fn(cols, rows))

            if best_img is None:
                skipped += 1
                print(f'  Seal {seal:2d}: SKIP (tiled, no render)')
                continue

            bbox = best_img.getbbox()
            if bbox:
                best_img = best_img.crop(bbox)
            out_path = output_path / f'seal_{seal:03d}.png'
            best_img.save(str(out_path))
            converted += 1
            w, h = best_img.size
            print(f'  Seal {seal:2d}: SAVED seal_{seal:03d}.png '
                  f'({w}x{h}, composite, pal={best_pal}, px={best_score})')

    print(f'\nDone: {converted} saved, {skipped} skipped')


if __name__ == '__main__':
    main()
