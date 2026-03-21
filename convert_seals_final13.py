"""
Pokémon Diamond Capsule Seal Extractor - FINAL v13
Key fixes from v12:
- Proper per-seal palette selection: nearest NCLR by file index + OAM palette
  field for sub-palette selection within the NCLR (no more brute-force)
- Fixed 1D vs 2D mapping detection: mapping_type != 0 means 1D linear (including
  type 16); sentinel values 0xFFFF properly rejected as invalid grid dimensions
- For 1D mapped sprites ncgr_tile_w is always set to 0 in render_cell so tiles
  are indexed sequentially (tile_idx, tile_idx+1, … in row-major order per OAM)
- Animation frames: render frame 0 as the default output; all frames are also
  written as a horizontal spritesheet into output_sheets/
- Fixed Pillow deprecation: list(img.getdata()) instead of img.getdata()
- Detailed file type mapping printed at startup
- Per-seal debug output shows palette file index and mapping mode
- Fixed 1D tile boundary scaling: NCER mapping_type now used to compute the
  correct OAM→tile-array index conversion (fixes scrambled seals 83, 88, 89, 90)

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
OUTPUT_SHEETS_FOLDER = "output_sheets"

OAM_SIZES = {
    (0, 0): (8, 8),   (0, 1): (16, 16), (0, 2): (32, 32), (0, 3): (64, 64),
    (1, 0): (16, 8),  (1, 1): (32, 8),  (1, 2): (32, 16), (1, 3): (64, 32),
    (2, 0): (8, 16),  (2, 1): (8, 32),  (2, 2): (16, 32), (2, 3): (32, 64),
}

# Default 1D tile-mapping boundary (bytes).  Matches NITRO mapping_type=16 (32-byte
# 1D boundary), and is also used as the fallback for 2D-mapped sprites where the
# boundary concept does not apply.
DEFAULT_1D_BOUNDARY = 32


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


def get_1d_boundary(ncer_mapping):
    """Convert NCER/NCGR mapping_type to the 1D tile-mapping boundary in bytes.

    Documented encodings (NITRO format):
      mapping_type == 0  → 2D mapping (use 32 as default boundary)
      mapping_type == 16 → 1D, 32-byte boundary
      mapping_type == 32 → 1D, 64-byte boundary
      mapping_type == 64 → 1D, 128-byte boundary
      ...
    For 1D modes: boundary_bytes = ncer_mapping * 2.
    """
    if ncer_mapping <= 0:
        return DEFAULT_1D_BOUNDARY
    return ncer_mapping * 2


def render_cell(cell_oams, tiles, colors, bpp, tile_offset=0, ncgr_tile_w=0, boundary=DEFAULT_1D_BOUNDARY):
    """Render one animation frame (cell) using OAM descriptors.

    ncgr_tile_w == 0  →  1D linear mapping: tiles are stored sequentially in
                          memory; for an OAM object of (tw × th) tiles the tile
                          number is ((base_tile + ty*tw + tx) * boundary)
                          // bytes_per_tile.
    ncgr_tile_w  > 0  →  2D VRAM mapping: tiles are laid out in a grid of
                          ncgr_tile_w columns; addressing is
                          (base_row + ty) * ncgr_tile_w + (base_col + tx).
    boundary          →  1D mapping boundary size in bytes (from NCER mapping_type).
                          OAM tile indices are in units of `boundary` bytes; the
                          actual tile-array index is scaled accordingly.
                          Examples: 4bpp + 32-byte boundary → scale 1 (unchanged);
                                    4bpp + 64-byte boundary → scale 2.
    """
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
    bytes_per_tile = 32 if bpp == 4 else 64

    for oam in cell_oams:
        ox = oam['x'] - min_x
        oy = oam['y'] - min_y
        tw = oam['w'] // 8
        th = oam['h'] // 8
        base_tile = oam['tile'] + tile_offset

        for ty in range(th):
            for tx in range(tw):
                if ncgr_tile_w > 0:
                    # 2D VRAM mapping: OAM tile index maps directly to grid position
                    base_col = base_tile % ncgr_tile_w
                    base_row = base_tile // ncgr_tile_w
                    tile_num = (base_row + ty) * ncgr_tile_w + (base_col + tx)
                else:
                    # 1D linear mapping: convert OAM character index (in boundary-
                    # sized units) to a tile-array index.
                    # For 4bpp+32B: scale=1 (unchanged); for 4bpp+64B: scale=2, etc.
                    tile_num = ((base_tile + ty * tw + tx) * boundary) // bytes_per_tile

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
    """Fallback renderer: lay tiles out in a grid (used when no NCER exists)."""
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
    """Count non-transparent pixels.  Uses list() to avoid Pillow deprecation."""
    if img is None:
        return 0
    return sum(1 for px in list(img.getdata()) if len(px) >= 4 and px[3] > 0)


def try_all_palettes(pal_list, render_fn):
    """Fallback: try every available palette and return the best-scoring result."""
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


def find_nearest_nclr(seal_idx, nclr_indices):
    """Return the NCLR file index whose position is closest to seal_idx."""
    if not nclr_indices:
        return None
    return min(nclr_indices, key=lambda x: abs(x - seal_idx))


def render_frame(cell_oams, tiles, pal_colors, pal_list, bpp, vram_w, boundary=DEFAULT_1D_BOUNDARY):
    """Render one frame, trying pal_colors first then falling back to all palettes."""
    best_img = None
    used_pal = None
    if pal_colors is not None:
        padded = pal_colors + [(0, 0, 0)] * max(0, 256 - len(pal_colors))
        try:
            img = render_cell(cell_oams, tiles, padded, bpp, 0, vram_w, boundary)
            if img is not None and img.getbbox() is not None:
                best_img = img.crop(img.getbbox())
        except Exception:
            pass
    if best_img is None:
        def render_fn(colors_):
            return render_cell(cell_oams, tiles, colors_, bpp, 0, vram_w, boundary)
        best_img, _, used_pal = try_all_palettes(pal_list, render_fn)
    return best_img, used_pal


def make_spritesheet(frames):
    """Combine frame images side-by-side into a horizontal spritesheet."""
    valid = [f for f in frames if f is not None]
    if not valid:
        return None
    max_w = max(f.size[0] for f in valid)
    max_h = max(f.size[1] for f in valid)
    sheet = Image.new('RGBA', (max_w * len(valid), max_h), (0, 0, 0, 0))
    for i, frame in enumerate(valid):
        sheet.paste(frame, (i * max_w, 0))
    return sheet


def main():
    input_path = Path(INPUT_FOLDER)
    output_path = Path(OUTPUT_FOLDER)
    sheets_path = Path(OUTPUT_SHEETS_FOLDER)
    output_path.mkdir(exist_ok=True)
    sheets_path.mkdir(exist_ok=True)

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

    # ── Detailed file-type mapping ────────────────────────────────────────────
    print("=== File Type Mapping ===")
    for idx in sorted(file_types.keys()):
        print(f"  {idx:3d}: {file_types[idx]}")
    print()

    # ── Load all palettes ─────────────────────────────────────────────────────
    palettes = {}
    for idx, typ in file_types.items():
        if typ == 'NCLR':
            colors = parse_nclr(file_data[idx])
            if colors:
                palettes[idx] = colors

    pal_list = sorted(palettes.items())
    print(f"Palettes found: {len(pal_list)}")
    for idx, colors in pal_list:
        print(f"  NCLR file {idx}: {len(colors)} colors")
    print()

    # NCLRs within files 0–91 are the per-seal (or per-category) palette files.
    # NCLRs outside that range (files 92+) are used only as a last resort.
    seal_nclr_indices = sorted(idx for idx in palettes if idx < 92)
    all_nclr_indices  = sorted(palettes.keys())

    # ── Shared NCER info ──────────────────────────────────────────────────────
    if 92 in file_data and file_types.get(92) == 'NCER':
        result = parse_ncer(file_data[92])
        if result:
            shared_ncer, _ = result
            print(f"  Shared NCER (file 92): {len(shared_ncer)} cells")
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

        # ── Parse per-seal NCER ───────────────────────────────────────────────
        cells = None
        ncer_mapping = 0
        if ncer_idx in file_data and file_types.get(ncer_idx) == 'NCER':
            result = parse_ncer(file_data[ncer_idx])
            if result:
                cells, ncer_mapping = result

        # ── 1D vs 2D mapping detection (FIX) ─────────────────────────────────
        # mapping_type == 0 with valid tile dimensions → 2D VRAM grid layout.
        # Anything else (including type 16 = 1D/32-byte boundary) → 1D linear.
        # tile_w/tile_h == 0xFFFF are sentinel values meaning "1D, no grid".
        has_valid_ncgr_dims = (0 < ncgr_tw < 0xFFFF and 0 < ncgr_th < 0xFFFF)
        use_2d = has_valid_ncgr_dims and (ncgr_mapping == 0)
        # For 1D mapping pass vram_w=0 → sequential tile indexing in render_cell
        vram_w = ncgr_tw if use_2d else 0
        mapping_mode = "2D" if use_2d else "1D"

        # Compute 1D tile-mapping boundary from the NCER mapping_type.
        # In 2D mode the boundary concept does not apply; use the default.
        boundary = DEFAULT_1D_BOUNDARY if use_2d else get_1d_boundary(ncer_mapping)

        non_empty_cells = [c for c in cells if c] if cells else []
        has_cells = bool(non_empty_cells)

        # ── Palette selection (FIX) ───────────────────────────────────────────
        # Find the NCLR whose file index is nearest to this seal's index.
        # The OAM palette field (already used in render_cell) then selects which
        # 16-colour sub-palette within that NCLR to apply.
        nclr_pool = seal_nclr_indices if seal_nclr_indices else all_nclr_indices
        nearest_pal_idx = find_nearest_nclr(seal, nclr_pool)
        if nearest_pal_idx is None:
            nearest_pal_idx = find_nearest_nclr(seal, all_nclr_indices)
        pal_colors = palettes.get(nearest_pal_idx) if nearest_pal_idx is not None else None

        if has_cells:
            print(f"    DEBUG seal {seal}: {n_tiles} tiles, NCGR={ncgr_tw}x{ncgr_th}, "
                  f"map={ncgr_mapping}, ncer_map={ncer_mapping}, boundary={boundary}B, "
                  f"{mapping_mode}, {len(non_empty_cells)} frame(s), "
                  f"palette_file={nearest_pal_idx}")

            # ── Render frame 0 as the default output (FIX) ───────────────────
            frame0, fallback_pal = render_frame(
                non_empty_cells[0], tiles, pal_colors, pal_list, bpp, vram_w, boundary)

            if frame0 is None:
                skipped += 1
                print(f"  Seal {seal:2d}: SKIP (no valid render)")
                continue

            out_path = output_path / f'seal_{seal:03d}.png'
            frame0.save(str(out_path))
            converted += 1
            w, h = frame0.size
            used_pal = nearest_pal_idx if fallback_pal is None else fallback_pal
            print(f"  Seal {seal:2d}: SAVED seal_{seal:03d}.png "
                  f"({w}x{h}, frame0, pal_file={used_pal}, {mapping_mode})")

            # ── Spritesheet for animated seals (FIX) ─────────────────────────
            if len(non_empty_cells) > 1:
                frames = [frame0]
                for cell_oams_f in non_empty_cells[1:]:
                    img_f, _ = render_frame(
                        cell_oams_f, tiles, pal_colors, pal_list, bpp, vram_w, boundary)
                    frames.append(img_f)
                sheet = make_spritesheet(frames)
                if sheet:
                    sheet_path = sheets_path / f'seal_{seal:03d}_sheet.png'
                    sheet.save(str(sheet_path))
                    n_frames = sum(1 for f in frames if f is not None)
                    print(f"  Seal {seal:2d}: SPRITESHEET {n_frames} frame(s) → "
                          f"seal_{seal:03d}_sheet.png")

        else:
            # ── Tiled fallback (no NCER cell data) ───────────────────────────
            if use_2d and ncgr_tw > 0:
                cols = ncgr_tw
                rows = ncgr_th if ncgr_th > 0 else math.ceil(n_tiles / cols)
            else:
                cols = math.ceil(math.sqrt(n_tiles))
                rows = math.ceil(n_tiles / cols)

            best_img = None
            if pal_colors is not None:
                padded = pal_colors + [(0, 0, 0)] * max(0, 256 - len(pal_colors))
                try:
                    best_img = render_tiled(tiles, padded, bpp, cols, rows)
                    if best_img is not None and best_img.getbbox() is None:
                        best_img = None
                except Exception:
                    best_img = None

            if best_img is None:
                def make_tiled_fn(cols_, rows_):
                    def fn(colors_):
                        return render_tiled(tiles, colors_, bpp, cols_, rows_)
                    return fn
                best_img, _, nearest_pal_idx = try_all_palettes(
                    pal_list, make_tiled_fn(cols, rows))

            if best_img is None:
                skipped += 1
                print(f"  Seal {seal:2d}: SKIP (tiled, no valid render)")
                continue

            bbox = best_img.getbbox()
            if bbox:
                best_img = best_img.crop(bbox)
            out_path = output_path / f'seal_{seal:03d}.png'
            best_img.save(str(out_path))
            converted += 1
            w, h = best_img.size
            print(f"  Seal {seal:2d}: SAVED seal_{seal:03d}.png "
                  f"({w}x{h}, tiled, pal_file={nearest_pal_idx}, {mapping_mode})")

    print(f"\nDone: {converted} saved, {skipped} skipped")


if __name__ == '__main__':
    main()
