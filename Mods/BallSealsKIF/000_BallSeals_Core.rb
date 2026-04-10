# 000_BallSeals_Core.rb
# ── Plugin registration ──────────────────────────────────────────
# Register with the Essentials PluginManager so the mod is visible
# to the engine's plugin system.  The guard avoids double-registration
# when meta.txt has already been parsed by the PluginManager loader.
if defined?(PluginManager) && PluginManager.respond_to?(:installed?) &&
   !PluginManager.installed?("Ball Seals")
  begin
    PluginManager.register({
      :name    => "Ball Seals",
      :version => "0.3.2",
      :link    => "https://github.com/SilvertongueRED/KIF-Pokeball-Seals",
      :credits => ["SilvertongueRED"]
    })
  rescue ArgumentError => e
    # KIF PluginManager may differ from standard Essentials;
    # meta.txt handles registration in that case.
    raise unless e.message.include?("comparison")
  end
end

$BallSealsKIFLoaded ||= false
module BallSealsKIF
  MOD_NAME = "BallSealsKIF"
  MOD_VERSION = "0.3.2"
  LOG_PATH = File.join(Dir.pwd, "Mods", "BallSealsKIF.log") rescue "BallSealsKIF.log"
  MAX_CAPSULES = 12
  MAX_SEALS_PER_CAPSULE = 8
  FX_SCALE = 3.0
  CANVAS_ICON_SIZE = 20

  # ── Seal list sorting ────────────────────────────────────────────
  # Persists for the session (across menu openings) but resets on
  # game restart.  :alpha = alphabetical, :recent = recently used first.
  @seal_sort_mode = :alpha
  def self.seal_sort_mode; @seal_sort_mode; end
  def self.seal_sort_mode=(v); @seal_sort_mode = v; end

  # ── Asset folder paths (relative to game root) ───────────────────
  GRAPHICS_BASE  = File.join("Graphics", "BallSeals")
  ICONS_DIR      = File.join(GRAPHICS_BASE, "Icons")
  GUI_DIR        = File.join(GRAPHICS_BASE, "GUI")

  # ── Dynamic game root detection ───────────────────────────────────
  # Tries multiple strategies to find the KIF game root directory.
  # Strategies run in order of reliability; the first successful match wins:
  # 1. Dir.pwd — RGSS sets the working directory to the game folder, so if
  #    Graphics/BallSeals/ exists there it is almost certainly correct.
  # 2. Traverse upward from __FILE__ looking for Graphics/BallSeals/ — the
  #    script's own location relative to the game root is very reliable.
  # 3. Walk $LOAD_PATH looking for a parent that contains Graphics/BallSeals/
  #    (specific subfolder to avoid false matches from engine/plugin dirs).
  # 4. Fall back to Dir.pwd unconditionally as a last resort.
  # Result is cached so detection only runs once.
  def self.detect_game_root
    return @game_root if defined?(@game_root) && @game_root

    # Strategy 1: Dir.pwd — RGSS sets the working directory to the game folder.
    # Check it first because it is cheap and usually correct.
    begin
      pwd = Dir.pwd
      if File.directory?(File.join(pwd, GRAPHICS_BASE))
        @game_root = pwd
        return @game_root
      end
    rescue SystemCallError
    end

    # Strategy 2: traverse upward from this script file (__FILE__).
    # BallSealsKIF/000_BallSeals_Core.rb lives at Mods/BallSealsKIF/ inside the
    # game tree, so walking up a few levels always reaches the game root.
    begin
      candidate = File.expand_path(File.dirname(__FILE__))
      8.times do
        if File.directory?(File.join(candidate, GRAPHICS_BASE))
          @game_root = candidate
          return @game_root
        end
        parent = File.dirname(candidate)
        break if parent == candidate
        candidate = parent
      end
    rescue SystemCallError
    end

    # Strategy 3: scan $LOAD_PATH entries for a parent containing Graphics/BallSeals/.
    # KIF/Essentials adds its script dirs to $LOAD_PATH; game root is typically
    # 1-3 levels above those dirs (Scripts/ → Data/ → game root is common).
    # We require the specific Graphics/BallSeals/ subfolder to avoid false
    # matches from engine or other plugin directories that have a Graphics/ folder.
    if defined?($LOAD_PATH)
      $LOAD_PATH.each do |lp|
        begin
          candidate = File.expand_path(lp.to_s)
          4.times do
            if File.directory?(File.join(candidate, GRAPHICS_BASE))
              @game_root = candidate
              return @game_root
            end
            parent = File.dirname(candidate)
            break if parent == candidate
            candidate = parent
          end
        rescue SystemCallError
        end
      end
    end

    # Strategy 4: Dir.pwd unconditionally as last resort
    @game_root = Dir.pwd rescue "."
    @game_root
  end

  # ── GUI image files (in GUI/ folder) ──────────────────────────────
  GUI_FILES = {
    :capsule_shape => "Pokeball.png",        # pokeball capsule overlay
    :capsule_bg    => "Display Boxes A.png", # seal case background
    :side_panel    => "Display Boxes B.png"  # info panel background
  }

  # ── Seal definitions ──────────────────────────────────────────────
  #  [symbol, display_name, fallback_color, fallback_size,
  #   particle_count, gravity, spin]
  #
  # 49 seal types organized into 10 groups matching the icon images.
  # Within each group, variants A-F/G produce increasing particle
  # counts while sharing the same animation sprite.
  SEAL_DEFS = [
    # Heart Seals (Heart Seal A – Heart Seal F)
    [:HEART_A,     "Heart Seal A",     Color.new(255, 90,140,220),  6,  2, 0.18, 0.10],
    [:HEART_B,     "Heart Seal B",     Color.new(255, 90,140,220),  6,  4, 0.18, 0.10],
    [:HEART_C,     "Heart Seal C",     Color.new(255, 90,140,220),  6,  6, 0.18, 0.10],
    [:HEART_D,     "Heart Seal D",     Color.new(255, 90,140,220),  6,  8, 0.18, 0.10],
    [:HEART_E,     "Heart Seal E",     Color.new(255, 90,140,220),  6, 10, 0.18, 0.10],
    [:HEART_F,     "Heart Seal F",     Color.new(255, 90,140,220),  6, 12, 0.18, 0.10],
    # Star Seals (Star Seal A – Star Seal F)
    [:STAR_A,      "Star Seal A",      Color.new(255,225,110,220),  6,  2, 0.16, 0.20],
    [:STAR_B,      "Star Seal B",      Color.new(255,225,110,220),  6,  4, 0.16, 0.20],
    [:STAR_C,      "Star Seal C",      Color.new(255,225,110,220),  6,  6, 0.16, 0.20],
    [:STAR_D,      "Star Seal D",      Color.new(255,225,110,220),  6,  8, 0.16, 0.20],
    [:STAR_E,      "Star Seal E",      Color.new(255,225,110,220),  6, 10, 0.16, 0.20],
    [:STAR_F,      "Star Seal F",      Color.new(255,225,110,220),  6, 12, 0.16, 0.20],
    # Line Seals (Line Seal A – Line Seal D)
    [:LINE_A,      "Line Seal A",      Color.new(255,255,170,220),  5,  2, 0.06, 0.00],
    [:LINE_B,      "Line Seal B",      Color.new(255,255,170,220),  5,  4, 0.06, 0.00],
    [:LINE_C,      "Line Seal C",      Color.new(255,255,170,220),  5,  6, 0.06, 0.00],
    [:LINE_D,      "Line Seal D",      Color.new(255,255,170,220),  5,  8, 0.06, 0.00],
    # Smoke Seals (Smoke Seal A – Smoke Seal D)
    [:SMOKE_A,     "Smoke Seal A",     Color.new(135,135,135,170),  8,  2,-0.02, 0.02],
    [:SMOKE_B,     "Smoke Seal B",     Color.new(135,135,135,170),  8,  4,-0.02, 0.02],
    [:SMOKE_C,     "Smoke Seal C",     Color.new(135,135,135,170),  8,  6,-0.02, 0.02],
    [:SMOKE_D,     "Smoke Seal D",     Color.new(135,135,135,170),  8,  8,-0.02, 0.02],
    # Song Seals (Song Seal A – Song Seal G)
    [:SONG_A,      "Song Seal A",      Color.new(185,120,255,220),  6,  2, 0.10, 0.08],
    [:SONG_B,      "Song Seal B",      Color.new(185,120,255,220),  6,  4, 0.10, 0.08],
    [:SONG_C,      "Song Seal C",      Color.new(185,120,255,220),  6,  6, 0.10, 0.08],
    [:SONG_D,      "Song Seal D",      Color.new(185,120,255,220),  6,  8, 0.10, 0.08],
    [:SONG_E,      "Song Seal E",      Color.new(185,120,255,220),  6, 10, 0.10, 0.08],
    [:SONG_F,      "Song Seal F",      Color.new(185,120,255,220),  6, 12, 0.10, 0.08],
    [:SONG_G,      "Song Seal G",      Color.new(185,120,255,220),  6, 14, 0.10, 0.08],
    # Fire Seals (Fire Seal A – Fire Seal D)
    [:FIRE_A,      "Fire Seal A",      Color.new(255,120, 60,220),  6,  2, 0.22, 0.08],
    [:FIRE_B,      "Fire Seal B",      Color.new(255,120, 60,220),  6,  4, 0.22, 0.08],
    [:FIRE_C,      "Fire Seal C",      Color.new(255,120, 60,220),  6,  6, 0.22, 0.08],
    [:FIRE_D,      "Fire Seal D",      Color.new(255,120, 60,220),  6,  8, 0.22, 0.08],
    # Party Seals (Party Seal A – Party Seal D)
    [:PARTY_A,     "Party Seal A",     Color.new(255,160,210,220),  4,  2, 0.18, 0.24],
    [:PARTY_B,     "Party Seal B",     Color.new(255,160,210,220),  4,  4, 0.18, 0.24],
    [:PARTY_C,     "Party Seal C",     Color.new(255,160,210,220),  4,  6, 0.18, 0.24],
    [:PARTY_D,     "Party Seal D",     Color.new(255,160,210,220),  4,  8, 0.18, 0.24],
    # Flora Seals (Flora Seal A – Flora Seal F)
    [:FLORA_A,     "Flora Seal A",     Color.new(110,220,120,220),  6,  2, 0.14, 0.12],
    [:FLORA_B,     "Flora Seal B",     Color.new(110,220,120,220),  6,  4, 0.14, 0.12],
    [:FLORA_C,     "Flora Seal C",     Color.new(110,220,120,220),  6,  6, 0.14, 0.12],
    [:FLORA_D,     "Flora Seal D",     Color.new(110,220,120,220),  6,  8, 0.14, 0.12],
    [:FLORA_E,     "Flora Seal E",     Color.new(110,220,120,220),  6, 10, 0.14, 0.12],
    [:FLORA_F,     "Flora Seal F",     Color.new(110,220,120,220),  6, 12, 0.14, 0.12],
    # Electric Seals (Electric Seal A – Electric Seal D)
    [:ELECTRIC_A,  "Electric Seal A",  Color.new(255,255,255,230),  4,  2, 0.10, 0.28],
    [:ELECTRIC_B,  "Electric Seal B",  Color.new(255,255,255,230),  4,  4, 0.10, 0.28],
    [:ELECTRIC_C,  "Electric Seal C",  Color.new(255,255,255,230),  4,  6, 0.10, 0.28],
    [:ELECTRIC_D,  "Electric Seal D",  Color.new(255,255,255,230),  4,  8, 0.10, 0.28],
    # Foamy Seals (Foamy Seal A – Foamy Seal D)
    [:FOAMY_A,     "Foamy Seal A",     Color.new(120,205,255,180),  7,  2,-0.03, 0.04],
    [:FOAMY_B,     "Foamy Seal B",     Color.new(120,205,255,180),  7,  4,-0.03, 0.04],
    [:FOAMY_C,     "Foamy Seal C",     Color.new(120,205,255,180),  7,  6,-0.03, 0.04],
    [:FOAMY_D,     "Foamy Seal D",     Color.new(120,205,255,180),  7,  8,-0.03, 0.04]
  ]

  # ── Icon file mapping (Icons/ folder — used for both GUI and battle) ─
  SEAL_ICON_FILES = {
    :HEART_A    => "Heart Seal A.png",    :HEART_B    => "Heart Seal B.png",
    :HEART_C    => "Heart Seal C.png",    :HEART_D    => "Heart Seal D.png",
    :HEART_E    => "Heart Seal E.png",    :HEART_F    => "Heart Seal F.png",
    :STAR_A     => "Star Seal A.png",     :STAR_B     => "Star Seal B.png",
    :STAR_C     => "Star Seal C.png",     :STAR_D     => "Star Seal D.png",
    :STAR_E     => "Star Seal E.png",     :STAR_F     => "Star Seal F.png",
    :LINE_A     => "Line Seal A.png",     :LINE_B     => "Line Seal B.png",
    :LINE_C     => "Line Seal C.png",     :LINE_D     => "Line Seal D.png",
    :SMOKE_A    => "Smoke Seal A.png",    :SMOKE_B    => "Smoke Seal B.png",
    :SMOKE_C    => "Smoke Seal C.png",    :SMOKE_D    => "Smoke Seal D.png",
    :SONG_A     => "Song Seal A.png",     :SONG_B     => "Song Seal B.png",
    :SONG_C     => "Song Seal C.png",     :SONG_D     => "Song Seal D.png",
    :SONG_E     => "Song Seal E.png",     :SONG_F     => "Song Seal F.png",
    :SONG_G     => "Song Seal G.png",
    :FIRE_A     => "Fire Seal A.png",     :FIRE_B     => "Fire Seal B.png",
    :FIRE_C     => "Fire Seal C.png",     :FIRE_D     => "Fire Seal D.png",
    :PARTY_A    => "Party Seal A.png",    :PARTY_B    => "Party Seal B.png",
    :PARTY_C    => "Party Seal C.png",    :PARTY_D    => "Party Seal D.png",
    :FLORA_A    => "Flora Seal A.png",    :FLORA_B    => "Flora Seal B.png",
    :FLORA_C    => "Flora Seal C.png",    :FLORA_D    => "Flora Seal D.png",
    :FLORA_E    => "Flora Seal E.png",    :FLORA_F    => "Flora Seal F.png",
    :ELECTRIC_A => "Electric Seal A.png", :ELECTRIC_B => "Electric Seal B.png",
    :ELECTRIC_C => "Electric Seal C.png", :ELECTRIC_D => "Electric Seal D.png",
    :FOAMY_A    => "Foamy Seal A.png",    :FOAMY_B    => "Foamy Seal B.png",
    :FOAMY_C    => "Foamy Seal C.png",    :FOAMY_D    => "Foamy Seal D.png"
  }

  # NOTE: The Animations/ folder has been merged into Icons/.  Battle
  # burst particles now use the same images shown in the GUI/editor.

  # ── Legacy seal symbol mapping (backward compat with older saves) ─
  LEGACY_SEAL_MAP = {
    :HEART    => :HEART_A,
    :STAR     => :STAR_A,
    :BUBBLE   => :FOAMY_A,
    :SPARK    => :ELECTRIC_A,
    :SMOKE    => :SMOKE_A,
    :NOTE     => :SONG_A,
    :FLOWER   => :FLORA_A,
    :LEAF     => :FLORA_B,
    :SNOW     => :FOAMY_B,
    :FIRE     => :FIRE_A,
    :RING     => :ELECTRIC_B,
    :DROPLET  => :FOAMY_C,
    :CONFETTI => :PARTY_A,
    :BEAM     => :LINE_A,
    :CLOUD    => :SMOKE_B,
    :FLASH    => :ELECTRIC_C,
    :ELE_A    => :ELECTRIC_A,
    :ELE_B    => :ELECTRIC_B,
    :ELE_C    => :ELECTRIC_C,
    :ELE_D    => :ELECTRIC_D,
    :ELE_E    => :ELECTRIC_D  # was 10 particles; maps to closest available (8)
  }

  @bitmaps ||= {}
  @active_fx ||= []
  @replacement_queue ||= []
  @graphics_hook_installed ||= false
  @menu_ensure_calls ||= 0
  @dynamic_seal_defs ||= []
  @dynamic_seal_icon_files ||= {}

  # ── Helpers ───────────────────────────────────────────────────────

  # Strips image file extension so paths work with RGSS/MKXP Bitmap.new,
  # which auto-detects format and does not expect an extension in the path.
  def self.strip_ext_for_rgss(path)
    path.sub(/\.(png|bmp|jpg|jpeg|gif)$/i, "")
  end

  # Tries to load a Bitmap from path with its extension; if that fails,
  # retries with the extension stripped (for RGSS/MKXP compatibility).
  # If the given path is absolute, also attempts the relative equivalent
  # (with and without extension) so that standard RGSS engines can resolve it.
  # Returns the Bitmap on success, or nil if all attempts fail.
  def self.load_bitmap_with_fallback(path)
    return nil if !path
    # Build a list of candidate paths to try, in priority order.
    candidates = [path]
    noext = strip_ext_for_rgss(path)
    candidates << noext if noext != path
    # If path looks absolute, also try the relative equivalent so that RGSS
    # (which resolves paths relative to the game root) can find the file.
    root = detect_game_root rescue nil
    if root
      sep = File::SEPARATOR
      prefix = root.end_with?(sep) ? root : "#{root}#{sep}"
      if path.start_with?(prefix)
        rel = path[prefix.length..]
        candidates << rel unless candidates.include?(rel)
        rel_noext = strip_ext_for_rgss(rel)
        candidates << rel_noext unless candidates.include?(rel_noext)
      end
    end
    candidates.each do |c|
      begin
        return Bitmap.new(c)
      rescue => e
        log("DBG: Bitmap.new(#{c}) failed: #{e.class}: #{e.message}") if $DEBUG
      end
    end
    log("load_bitmap_with_fallback: could not load #{path} after trying #{candidates.length} variants")
    nil
  end

  def self.log(msg)
    begin
      File.open(LOG_PATH, "a") { |f| f.puts("[#{Time.now}] #{msg}") }
    rescue
    end
  end

  def self.intl(str, *args)
    begin
      return _INTL(str, *args)
    rescue
      txt = str.to_s.dup
      args.each_with_index { |arg, i| txt.gsub!("{#{i + 1}}", arg.to_s) }
      return txt
    end
  end

  def self.resolve_seal_sym(sym)
    sym = sym.to_sym rescue sym
    return LEGACY_SEAL_MAP[sym] if LEGACY_SEAL_MAP.key?(sym)
    sym
  end

  # ── Dynamic seal scanning ──────────────────────────────────────────
  # Scans the Icons/ folder at init time and registers any PNG file that
  # is not already listed in SEAL_ICON_FILES.  This allows new seal
  # images (e.g. letter seals A-Z, Water Drop Seal, Starburst Seal, …)
  # to be used in-game simply by dropping them into the Icons/ folder.
  def self.scan_icons_folder
    @dynamic_seal_defs = []
    @dynamic_seal_icon_files = {}
    root = detect_game_root rescue nil
    if !root
      log("scan_icons_folder: could not detect game root")
      return
    end
    icons_abs = File.join(root, ICONS_DIR)
    return if !File.directory?(icons_abs)
    existing_filenames = SEAL_ICON_FILES.values.map { |f| f.downcase }
    Dir.glob(File.join(icons_abs, "*.png")).sort.each do |abs_path|
      filename = File.basename(abs_path)
      next if existing_filenames.include?(filename.downcase)
      name = filename.sub(/\.png$/i, "")
      sym = name.upcase.gsub(/\s+/, "_").gsub(/[^A-Z0-9_]/, "").to_sym
      next if sym == :"" || sym.to_s.empty?
      next if SEAL_DEFS.any? { |s| s[0] == sym }
      next if @dynamic_seal_defs.any? { |s| s[0] == sym }
      @dynamic_seal_defs << [sym, name, Color.new(255, 255, 255, 220), 6, 4, 0.12, 0.06]
      @dynamic_seal_icon_files[sym] = filename
    end
    log("Scanned Icons folder: found #{@dynamic_seal_defs.length} additional seal(s)")
  rescue => e
    log("scan_icons_folder ERROR: #{e.class}: #{e.message}")
  end

  def self.all_seal_defs
    combined = SEAL_DEFS + (@dynamic_seal_defs || [])
    regular = []
    letters = []
    punctuation = []
    combined.each do |s|
      name = s[1].to_s
      if name =~ /\A[A-Za-z] Seal\z/
        letters << s
      elsif name =~ /Exclamation Mark Seal|Question Mark Seal/i
        punctuation << s
      else
        regular << s
      end
    end
    regular.sort_by { |s| s[1].downcase } +
      letters.sort_by { |s| s[1].downcase } +
      punctuation.sort_by { |s| s[1].downcase }
  end

  # Returns only shape/effect seals (everything except letters and punctuation).
  def self.shape_seal_defs
    combined = SEAL_DEFS + (@dynamic_seal_defs || [])
    combined.select { |s|
      name = s[1].to_s
      !(name =~ /\A[A-Za-z] Seal\z/) && !(name =~ /Exclamation Mark Seal|Question Mark Seal/i)
    }.sort_by { |s| s[1].downcase }
  end

  # Returns only letter and punctuation (? !) seals.
  def self.letter_seal_defs
    combined = SEAL_DEFS + (@dynamic_seal_defs || [])
    letters = []
    punctuation = []
    combined.each do |s|
      name = s[1].to_s
      if name =~ /\A[A-Za-z] Seal\z/
        letters << s
      elsif name =~ /Exclamation Mark Seal|Question Mark Seal/i
        punctuation << s
      end
    end
    letters.sort_by { |s| s[1].downcase } +
      punctuation.sort_by { |s| s[1].downcase }
  end

  # ── Seal usage tracking (for "recently added" sorting) ───────────
  # Maintains an ordered list of seal symbols in the global save data.
  # The most recently placed seal is at the END of the array.  This
  # list is persisted across saves so the sort order is stable.

  def self.seal_use_order
    data = ensure_global_data
    return [] if !data
    data[:seal_use_order] ||= []
    data[:seal_use_order]
  end

  def self.record_seal_use(sym)
    data = ensure_global_data
    return if !data
    data[:seal_use_order] ||= []
    data[:seal_use_order].delete(sym)
    data[:seal_use_order] << sym
  end

  # Sort a seal def list according to the current seal_sort_mode.
  # :alpha  — alphabetical by display name (default)
  # :recent — most recently used seals first; unused seals at the end
  def self.sorted_seal_defs(defs)
    return defs if !defs || defs.empty?
    case @seal_sort_mode
    when :recent
      order = seal_use_order
      defs.sort_by do |s|
        idx = order.index(s[0])
        idx ? -(idx + 1) : 0   # used seals sort by recency (newest first); unused seals last
      end
    else # :alpha
      defs.sort_by { |s| s[1].downcase }
    end
  end

  def self.sort_mode_label
    case @seal_sort_mode
    when :recent then intl("Sort: Recent")
    else              intl("Sort: A-Z")
    end
  end

  def self.toggle_seal_sort_mode
    @seal_sort_mode = (@seal_sort_mode == :alpha) ? :recent : :alpha
  end

  # Returns true if the seal symbol corresponds to a letter or punctuation seal.
  def self.letter_seal?(sym)
    name = seal_name(sym).to_s
    !!(name =~ /\A[A-Za-z] Seal\z/ || name =~ /Exclamation Mark Seal|Question Mark Seal/i)
  end

  # Creates a new bitmap with a 1px black outline around the original.
  # Used for letter/punctuation seals in battle bursts for readability.
  @outlined_bitmaps ||= {}
  def self.outlined_bitmap_for(sym)
    return @outlined_bitmaps[sym] if @outlined_bitmaps[sym] && !@outlined_bitmaps[sym].disposed?
    src = bitmap_for(sym)
    return src if !src || (src.respond_to?(:disposed?) && src.disposed?)
    w = src.width
    h = src.height
    outlined = Bitmap.new(w + 2, h + 2)
    src_rect = Rect.new(0, 0, w, h)
    # Draw the source shifted in 8 directions as black shadow for outline
    offsets = [[-1,-1],[0,-1],[1,-1],[-1,0],[1,0],[-1,1],[0,1],[1,1]]
    # Create a solid black version of the source (preserving alpha)
    black_bmp = Bitmap.new(w, h)
    (0...h).each do |py|
      (0...w).each do |px|
        pixel = src.get_pixel(px, py)
        next if pixel.alpha == 0
        # Cap outline alpha at 200 to keep a slight translucency on edges
        black_bmp.set_pixel(px, py, Color.new(0, 0, 0, [pixel.alpha, 200].min))
      end
    end
    # Draw black outlines, then original on top
    offsets.each do |dx, dy|
      outlined.blt(1 + dx, 1 + dy, black_bmp, Rect.new(0, 0, w, h))
    end
    outlined.blt(1, 1, src, src_rect)
    black_bmp.dispose
    @outlined_bitmaps[sym] = outlined
    outlined
  rescue => e
    log("outlined_bitmap_for ERROR: #{e.class}: #{e.message}")
    bitmap_for(sym)
  end

  def self.all_seal_icon_files
    SEAL_ICON_FILES.merge(@dynamic_seal_icon_files || {})
  end

  def self.seal_defs; all_seal_defs; end
  def self.seal_ids; all_seal_defs.map { |s| s[0] }; end

  def self.seal_name(sym)
    sym = resolve_seal_sym(sym)
    found = all_seal_defs.find { |s| s[0] == sym }
    return found ? found[1] : sym.to_s
  end

  def self.seal_style(sym)
    sym = resolve_seal_sym(sym)
    found = all_seal_defs.find { |s| s[0] == sym }
    return found || SEAL_DEFS[0]
  end

  # ── Save data ─────────────────────────────────────────────────────

  def self.ensure_global_data
    return nil if !$PokemonGlobal
    data = $PokemonGlobal.instance_variable_get(:@ball_seals_kif)
    if !data || !data.is_a?(Hash)
      data = {
        :capsules  => Array.new(MAX_CAPSULES) { |i| default_capsule(i + 1) },
        :inventory => default_inventory
      }
      $PokemonGlobal.instance_variable_set(:@ball_seals_kif, data)
    end
    data[:capsules] ||= Array.new(MAX_CAPSULES) { |i| default_capsule(i + 1) }
    data[:inventory] ||= default_inventory
    return data
  end

  def self.default_inventory
    h = {}
    all_seal_defs.each { |s| h[s[0]] = 99 }
    return h
  end

  def self.inventory
    data = ensure_global_data
    return data ? data[:inventory] : default_inventory
  end

  def self.default_capsule(slot)
    { :name => sprintf("CAPSULE %02d", slot), :placements => [] }
  end

  def self.capsules
    data = ensure_global_data
    return data ? data[:capsules] : Array.new(MAX_CAPSULES) { |i| default_capsule(i + 1) }
  end

  def self.capsule(slot)
    return nil if slot.nil? || slot < 1 || slot > MAX_CAPSULES
    return capsules[slot - 1]
  end

  def self.set_capsule(slot, cap)
    return if slot.nil? || slot < 1 || slot > MAX_CAPSULES
    data = ensure_global_data
    if !data
      pbMessage(intl("Please load a save file first.")) if defined?(pbMessage)
      return
    end
    data[:capsules][slot - 1] = cap
  end

  def self.clone_capsule(cap)
    {
      :name => (cap[:name] || "CAPSULE"),
      :placements => (cap[:placements] || []).map { |p|
        { :seal => resolve_seal_sym(p[:seal]), :x => p[:x], :y => p[:y] }
      }
    }
  end

  def self.inject_accessors
    if defined?(Pokemon)
      Pokemon.class_eval do
        def ball_capsule_slot; @ball_capsule_slot; end
        def ball_capsule_slot=(val); @ball_capsule_slot = val; end
        def ball_seals; @ball_seals ||= []; @ball_seals; end
        def ball_seals=(arr); @ball_seals = (arr || []).map { |x| x.is_a?(String) ? x.to_sym : x }.compact; end
      end
    end
    if defined?(PokeBattle_Pokemon)
      PokeBattle_Pokemon.class_eval do
        def ball_capsule_slot; @ball_capsule_slot; end
        def ball_capsule_slot=(val); @ball_capsule_slot = val; end
        def ball_seals; @ball_seals ||= []; @ball_seals; end
        def ball_seals=(arr); @ball_seals = (arr || []).map { |x| x.is_a?(String) ? x.to_sym : x }.compact; end
      end
    end
  end

  def self.party
    return $player.party if defined?($player) && $player && $player.respond_to?(:party)
    return $Trainer.party if defined?($Trainer) && $Trainer && $Trainer.respond_to?(:party)
    []
  end

  def self.choose_party_pokemon(title = nil)
    mons = party
    return nil if !mons || mons.empty?
    commands = mons.each_with_index.map do |pkmn, i|
      slot = pkmn.respond_to?(:ball_capsule_slot) ? pkmn.ball_capsule_slot : nil
      captxt = slot ? " [C#{slot}]" : ""
      "#{i + 1}. #{pkmn.name}#{captxt}"
    end
    idx = BallSealsCommandScene.new(title || intl("Choose a Pokémon."), commands, intl("Choose a party Pokémon.")).main
    return nil if idx.nil?
    mons[idx]
  rescue => e
    log("choose_party_pokemon ERROR: #{e.class}: #{e.message}")
    pbMessage(intl("Ball Seals error: {1}", e.message.to_s[0, 60])) if defined?(pbMessage)
    nil
  end

  def self.capsule_for_pokemon(pkmn)
    return nil if !pkmn
    slot = nil
    slot = pkmn.ball_capsule_slot if pkmn.respond_to?(:ball_capsule_slot)
    if slot && slot >= 1 && slot <= MAX_CAPSULES
      cap = capsule(slot)
      return clone_capsule(cap) if cap
    end
    if pkmn.respond_to?(:ball_seals) && pkmn.ball_seals && !pkmn.ball_seals.empty?
      placements = []
      pkmn.ball_seals[0, MAX_SEALS_PER_CAPSULE].each_with_index do |seal, i|
        ang = (i.to_f / [1, pkmn.ball_seals.length].max) * Math::PI * 2.0
        placements << {
          :seal => resolve_seal_sym(seal),
          :x => 0.5 + Math.cos(ang) * 0.41,
          :y => 0.5 + Math.sin(ang) * 0.32
        }
      end
      return { :name => "Legacy", :placements => placements }
    end
    nil
  end

  def self.enqueue_capsule_for_pokemon(pkmn, idx_battler = nil)
    cap = capsule_for_pokemon(pkmn)
    @replacement_queue << { :cap => cap, :idx_battler => idx_battler }
  end

  def self.clear_replacement_queue; @replacement_queue = []; end
  def self.replacement_queue_pending?; !@replacement_queue.empty?; end
  def self.consume_replacement_capsule
    return nil if @replacement_queue.empty?
    entry = @replacement_queue.shift
    # Support both old (bare capsule) and new (hash with :cap/:idx_battler) formats
    entry.is_a?(Hash) && entry.key?(:cap) ? entry : { :cap => entry, :idx_battler => nil }
  end

  # ── Asset path helpers ────────────────────────────────────────────

  def self.icon_path(sym)
    sym = resolve_seal_sym(sym)
    filename = all_seal_icon_files[sym]
    return nil if !filename
    rel = File.join(ICONS_DIR, filename)
    abs = File.join(detect_game_root, rel) rescue nil
    log("DBG: icon_path verified file exists: #{abs}") if $DEBUG && abs && File.exist?(abs)
    # Always return relative path — RGSS Bitmap.new expects paths relative to
    # the game root; load_bitmap_with_fallback will handle extension stripping.
    rel
  end

  # After the Icons/Animations merge, animation_path is an alias for
  # icon_path — both GUI and battle use the same Icons/ images.
  def self.animation_path(sym)
    icon_path(sym)
  end

  def self.gui_path(key)
    filename = GUI_FILES[key]
    return nil if !filename
    rel = File.join(GUI_DIR, filename)
    abs = File.join(detect_game_root, rel) rescue nil
    log("DBG: gui_path verified file exists: #{abs}") if $DEBUG && abs && File.exist?(abs)
    rel
  end

  # ── Bitmap loading ────────────────────────────────────────────────

  # Returns icon bitmap for menu/editor display and battle particles (Icons/ folder).
  def self.bitmap_for(sym)
    sym = resolve_seal_sym(sym)
    return @bitmaps[sym] if @bitmaps[sym] && !@bitmaps[sym].disposed?
    path = icon_path(sym)
    bmp = load_bitmap_with_fallback(path)
    if bmp
      @bitmaps[sym] = bmp
      return @bitmaps[sym]
    end
    log("WARN: bitmap_for(#{sym}) could not load custom icon from #{path.inspect}; using coded fallback. Check game root: #{detect_game_root}")
    style = seal_style(sym)
    size = style[3] || 6
    bmp = Bitmap.new(size, size)
    c = style[2] || Color.new(255,255,255,220)
    bmp.fill_rect(0, 0, size, size, c)
    @bitmaps[sym] = bmp
    bmp
  end

  # Returns the particle bitmap for pokeball burst (Icons/ folder).
  # After the Icons/Animations merge, this delegates to bitmap_for —
  # the same image shown in the editor is used in battle.
  def self.animation_bitmap_for(sym)
    bitmap_for(sym)
  end

  # Returns a GUI element bitmap (GUI/ folder).
  def self.gui_bitmap(key)
    cache_key = :"gui_#{key}"
    return @bitmaps[cache_key] if @bitmaps[cache_key] && !@bitmaps[cache_key].disposed?
    path = gui_path(key)
    bmp = load_bitmap_with_fallback(path)
    if bmp
      @bitmaps[cache_key] = bmp
      return @bitmaps[cache_key]
    end
    log("WARN: gui_bitmap(#{key}) could not load custom graphic from #{path.inspect}; returning nil. Check game root: #{detect_game_root}")
    @bitmaps[cache_key] = nil
    nil
  end

  # ── Canvas drawing ────────────────────────────────────────────────

  def self.draw_capsule_shape(bitmap, x, y, w, h, fill, border)
    rx = w / 2.0
    ry = h / 2.0
    cx = x + rx
    cy = y + ry
    (y...(y + h)).each do |py|
      (x...(x + w)).each do |px|
        nx = (px - cx) / rx
        ny = (py - cy) / ry
        d = nx * nx + ny * ny
        if d <= 1.0
          bitmap.set_pixel(px, py, fill)
        elsif d <= 1.08
          bitmap.set_pixel(px, py, border)
        end
      end
    end
  rescue
    bitmap.fill_rect(x, y, w, h, fill)
  end

  def self.draw_icon(bitmap, bx, px, py, size)
    return if !bitmap || !bx
    dest = Rect.new(px - size / 2, py - size / 2, size, size)
    src = Rect.new(0, 0, bx.width, bx.height)
    bitmap.stretch_blt(dest, bx, src)
  rescue
    bitmap.blt(px - bx.width/2, py - bx.height/2, bx, Rect.new(0,0,bx.width,bx.height))
  end

  def self.refresh_capsule_canvas(bitmap, cap, cursor_x = nil, cursor_y = nil, cursor_seal = nil)
    return if !bitmap
    bitmap.clear
    bg = Color.new(18, 22, 30)
    bitmap.fill_rect(0, 0, bitmap.width, bitmap.height, bg)
    # Try the GUI capsule shape image as an overlay; fall back to
    # the procedurally drawn ellipse.
    capsule_bmp = gui_bitmap(:capsule_shape)
    if capsule_bmp
      dest = Rect.new(16, 12, bitmap.width - 32, bitmap.height - 24)
      src  = Rect.new(0, 0, capsule_bmp.width, capsule_bmp.height)
      bitmap.stretch_blt(dest, capsule_bmp, src)
    else
      fill   = Color.new(70, 80, 98)
      border = Color.new(210, 220, 235)
      draw_capsule_shape(bitmap, 16, 12, bitmap.width - 32, bitmap.height - 24, fill, border)
    end
    bitmap.fill_rect(20, bitmap.height/2 - 1, bitmap.width - 40, 2, Color.new(120,140,160,120))
    # Vertical center line: offset 1.5% right of true center (was 0.75%, shifted +0.75%)
    vert_x = (bitmap.width / 2.0 + bitmap.width * 0.015).to_i - 1
    bitmap.fill_rect(vert_x, 18, 2, bitmap.height - 36, Color.new(120,140,160,100))
    cap = cap || { :placements => [] }
    cap[:placements].each do |pl|
      bx = bitmap_for(pl[:seal])
      next if !bx
      px = 16 + (pl[:x].to_f * (bitmap.width - 32)).to_i
      py = 12 + (pl[:y].to_f * (bitmap.height - 24)).to_i
      draw_icon(bitmap, bx, px, py, CANVAS_ICON_SIZE)
    end
    if !cursor_x.nil? && !cursor_y.nil?
      px = 16 + (cursor_x.to_f * (bitmap.width - 32)).to_i
      py = 12 + (cursor_y.to_f * (bitmap.height - 24)).to_i
      # Draw a semi-transparent shadow of the seal being placed at the cursor
      if cursor_seal
        shadow_bmp = bitmap_for(cursor_seal)
        if shadow_bmp
          size = CANVAS_ICON_SIZE
          dest = Rect.new(px - size / 2, py - size / 2, size, size)
          src  = Rect.new(0, 0, shadow_bmp.width, shadow_bmp.height)
          # Create a temporary bitmap to draw the seal at reduced opacity
          temp = Bitmap.new(size, size)
          temp.stretch_blt(Rect.new(0, 0, size, size), shadow_bmp, src)
          # Blit with reduced opacity for a shadow/ghost effect
          bitmap.blt(px - size / 2, py - size / 2, temp, Rect.new(0, 0, size, size), 120)
          temp.dispose
        end
      end
      c = Color.new(255,255,255)
      bitmap.fill_rect(px - 7, py, 15, 1, c)
      bitmap.fill_rect(px, py - 7, 1, 15, c)
      bitmap.fill_rect(px - 2, py - 2, 5, 5, Color.new(255,255,255,50))
    end
  end

  # ── Pokeball opening burst animation ──────────────────────────────

  # Burst delay (in frames) added when Ghost Classic+ UI is detected.
  # Ghost's vanilla scene opens the pokéball slightly later than EBDX,
  # so the seal burst needs a matching stagger to stay in sync.
  GHOST_BURST_DELAY = 12

  # Detect whether Ghost Classic+ UI mod is installed and active.
  # Checks for the characteristic aliases it applies to PokeBattle_Scene.
  # The result is cached per session; init_battle resets the cache so
  # removing/adding Ghost is picked up after a game restart.
  def self.ghost_classic_installed?
    return @ghost_classic_detected unless @ghost_classic_detected.nil?
    @ghost_classic_detected = false
    begin
      scene_klass = resolve_scene_class
      if scene_klass &&
         scene_klass.method_defined?(:ghost_classicplus_substitute_pbStartBattle) &&
         scene_klass.method_defined?(:pbRefreshBattlerTones)
        @ghost_classic_detected = true
      end
    rescue
    end
    @ghost_classic_detected
  end

  def self.start_capsule_burst_on_viewport(viewport, x, y, cap, burst_delay = 0)
    return if !cap || !cap[:placements] || cap[:placements].empty?
    return if !viewport || (viewport.respond_to?(:disposed?) && viewport.disposed?)
    # Sort placements by x-position so the left-to-right GUI arrangement
    # is preserved as the display/animation order during battle.
    sorted = cap[:placements].sort_by { |pl| pl[:x].to_f }
    # All seals animate at the exact same time (no stagger delay) but are
    # drawn in left-to-right order matching their GUI placement sequence.
    sorted.each_with_index do |pl, seal_idx|
      style = seal_style(pl[:seal])
      sym   = style[0]
      bmp   = letter_seal?(sym) ? outlined_bitmap_for(sym) : animation_bitmap_for(sym)
      next if !bmp || (bmp.respond_to?(:disposed?) && bmp.disposed?)
      count = style[4] || 10
      grav  = style[5] || 0.12
      spin  = style[6] || 0.10
      ox = ((pl[:x].to_f - 0.5) * 393).to_i
      oy = ((pl[:y].to_f - 0.5) * 306).to_i
      sp = Sprite.new(viewport)
      sp.bitmap = bmp
      sp.ox = bmp.width / 2
      sp.oy = bmp.height / 2
      sp.x = x + ox
      sp.y = y + oy
      sp.z = 999999
      sp.opacity = 0
      sp.zoom_x = FX_SCALE
      sp.zoom_y = FX_SCALE
      # Still animation: particles stay at their placed position without
      # drifting, gravity, or spin so letter/shape seals are easy to read.
      vx  = 0
      vy  = 0
      rot = 0
      vr  = 0
      particles = [[sp, vx, vy, 0, rot, vr]]
      # All seals start simultaneously — optional burst_delay staggers them
      # when Ghost Classic+ shifts the ball-open timing later.
      # :hold keeps seals at full opacity for ~2 seconds (40 frames at 20fps)
      # before the fade-out begins.
      started = burst_delay <= 0
      @active_fx << { :vp => viewport, :frames => 38, :delay => burst_delay,
                      :hold => 40, :started => started, :particles => particles }
      # Make visible immediately only when there is no burst delay
      if started
        particles.each { |p| p[0].opacity = 255 if p[0] && !p[0].disposed? }
      end
    end
    safe_play_se("Pkmn send out")
    log("DBG: Started capsule burst with #{cap[:placements].length} placements at (#{x},#{y})")
  rescue => e
    log("start_capsule_burst_on_viewport ERROR: #{e.class}: #{e.message}")
  end

  def self.safe_play_se(name)
    return if !defined?(pbSEPlay)
    pbSEPlay(name)
  rescue
  end

  def self.update_effects
    return if !@active_fx || @active_fx.empty?
    keep = []
    @active_fx.each do |fx|
      # Handle staggered delay — wait before starting animation
      if fx[:delay] && fx[:delay] > 0
        fx[:delay] -= 1
        keep << fx
        next
      end
      # First frame after delay expires: make particles visible
      if fx[:started] == false
        fx[:started] = true
        fx[:particles].each do |p|
          sp = p[0]
          sp.opacity = 255 if sp && !sp.disposed?
        end
      end
      # Hold phase — keep seals at full opacity for :hold frames (~2 s)
      # before beginning the fade-out.
      if fx[:hold] && fx[:hold] > 0
        fx[:hold] -= 1
        keep << fx
        next
      end
      fx[:frames] -= 1
      denom = [1, fx[:frames] + 1].max
      fx[:particles].each do |p|
        sp, vx, vy, grav, rot, vr = p
        next if !sp || sp.disposed?
        sp.x += vx
        sp.y += vy
        vy += grav
        rot += vr
        sp.angle = rot
        sp.opacity = [0, sp.opacity - (255 / denom)].max
        p[2] = vy
        p[4] = rot
      end
      if fx[:frames] <= 0
        fx[:particles].each do |p2|
          sp2 = p2[0]
          sp2.dispose if sp2 && !sp2.disposed?
        end
      else
        keep << fx
      end
    end
    @active_fx = keep
  rescue => e
    log("update_effects ERROR: #{e.class}: #{e.message}")
  end

  # ── Viewport helpers ──────────────────────────────────────────────

  def self.resolve_test_viewport(scene)
    if scene
      [:@viewport, :@viewport1, :@viewport2, :@viewport0].each do |iv|
        next if !scene.instance_variable_defined?(iv)
        vp = scene.instance_variable_get(iv)
        return vp if vp && vp.is_a?(Viewport) && !vp.disposed?
      end
    end
    Viewport.new(0,0,Graphics.width,Graphics.height)
  rescue
    Viewport.new(0,0,Graphics.width,Graphics.height)
  end

  def self.test_capsule(cap)
    sc = ($scene rescue nil)
    vp = resolve_test_viewport(sc)
    start_capsule_burst_on_viewport(vp, Graphics.width / 2, Graphics.height / 2, cap)
  end

  def self.preview_capsule(cap)
    return if !cap || !cap[:placements] || cap[:placements].empty?
    sc = ($scene rescue nil)
    vp = resolve_test_viewport(sc)
    owns_viewport = false
    if vp.nil? || (vp.respond_to?(:disposed?) && vp.disposed?)
      vp = Viewport.new(0,0,Graphics.width,Graphics.height)
      owns_viewport = true
    end
    start_capsule_burst_on_viewport(vp, Graphics.width / 2, Graphics.height / 2, cap)
    # hold (40) + fade (38) + small buffer (4) = total preview frames
    preview_frames = 40 + 38 + 4
    preview_frames.times do
      Graphics.update
      begin
        Input.update
      rescue
      end
    end
    vp.dispose if owns_viewport && vp && !vp.disposed?
  rescue => e
    log("preview_capsule ERROR: #{e.class}: #{e.message}")
  end

  # ── Engine hooks ──────────────────────────────────────────────────

  def self.tick
    frame = (Graphics.frame_count rescue nil)
    return if frame && @last_tick_frame == frame
    @last_tick_frame = frame
    update_effects
  rescue => e
    log("tick ERROR: #{e.class}: #{e.message}")
  end

  def self.install_graphics_tick_hook
    return if @graphics_hook_installed
    return if !defined?(Graphics)
    eigen = class << Graphics; self; end
    unless eigen.method_defined?(:__bskif_update_orig)
      eigen.class_eval do
        alias_method :__bskif_update_orig, :update
        define_method(:update) do |*args|
          __bskif_update_orig(*args)
          BallSealsKIF.tick
        end
      end
    end
    @graphics_hook_installed = true
  rescue => e
    log("install_graphics_tick_hook ERROR: #{e.class}: #{e.message}")
  end

  def self.init
    inject_accessors
    scan_icons_folder
    ensure_global_data
    install_graphics_tick_hook
    log("=== #{MOD_NAME} #{MOD_VERSION} init ===")
    root = detect_game_root
    log("Game root detected: #{root}")
    [
      ["Icons",      File.join(root, ICONS_DIR)],
      ["GUI",        File.join(root, GUI_DIR)]
    ].each do |label, dir|
      if File.directory?(dir)
        count = Dir.glob(File.join(dir, "*.png")).length rescue 0
        log("  #{label} folder found (#{count} PNG files): #{dir}")
      else
        log("  #{label} folder NOT found at: #{dir}")
      end
    end
  rescue => e
    log("init ERROR: #{e.class}: #{e.message}")
  end
end

class BallSealsCommandScene
  def initialize(title, commands, help_text = nil, initial_index = 0, width = nil, icons = nil)
    @title = title
    @commands = commands
    @help_text = help_text
    @initial_index = initial_index || 0
    @width = width || [Graphics.width - 32, 340].max
    @icons = icons
  end

  def main
    @viewport = Viewport.new(0,0,Graphics.width,Graphics.height)
    @viewport.z = 99999
    @sprites = {}
    @sprites["bg"] = Sprite.new(@viewport)
    @sprites["bg"].bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @sprites["bg"].bitmap.fill_rect(0,0,Graphics.width,Graphics.height,Color.new(14,18,24))
    safe_title = @title.to_s
    safe_title = safe_title[0, 28]
    @sprites["title"] = Window_UnformattedTextPokemon.newWithSize(safe_title, 0, 0, Graphics.width, 64, @viewport)

    help_h = (@help_text && !@help_text.empty?) ? 80 : 0
    line_h = 34
    desired_h = (@commands.length * line_h) + 32
    win_h = [desired_h, Graphics.height - 96 - help_h].min
    has_icons = @icons.is_a?(Array) && !@icons.empty?
    win_w = has_icons ? [[@width, Graphics.width - 100].min, 240].max : [@width, Graphics.width - 32].min
    x = has_icons ? 16 : (Graphics.width - win_w) / 2
    y = 68
    @sprites["cmd"] = Window_CommandPokemon.newWithSize(@commands, x, y, win_w, win_h, @viewport)
    @sprites["cmd"].index = [[@initial_index, 0].max, @commands.length - 1].min
    # Icon preview panel on the right side (when icons are provided)
    if has_icons
      panel_x = x + win_w + 24
      panel_y = y
      panel_bmp = BallSealsKIF.gui_bitmap(:side_panel)
      if panel_bmp
        dest = Rect.new(panel_x - 8, panel_y, Graphics.width - panel_x, win_h)
        src  = Rect.new(0, 0, panel_bmp.width, panel_bmp.height)
        @sprites["bg"].bitmap.stretch_blt(dest, panel_bmp, src)
      end
      @sprites["icon_preview"] = Sprite.new(@viewport)
      @sprites["icon_preview"].x = panel_x + (Graphics.width - panel_x) / 2 - 21 - (Graphics.width * 4 / 100)
      @sprites["icon_preview"].y = panel_y + 16 + (Graphics.height * 5 / 100)
      @sprites["icon_preview"].zoom_x = 3.0
      @sprites["icon_preview"].zoom_y = 3.0
      @last_icon_index = -1
      update_icon_preview
    end
    if help_h > 0
      @sprites["help"] = Window_UnformattedTextPokemon.newWithSize(@help_text.to_s, 0, Graphics.height - help_h, Graphics.width, help_h, @viewport)
    end

    loop do
      Graphics.update
      Input.update
      @sprites["cmd"].update
      update_icon_preview if has_icons
      if Input.trigger?(Input::USE)
        ret = @sprites["cmd"].index
        dispose
        return ret
      elsif Input.trigger?(Input::BACK)
        dispose
        return nil
      end
    end
  end

  def update_icon_preview
    return if !@icons || !@sprites["icon_preview"]
    idx = @sprites["cmd"].index rescue 0
    return if idx == @last_icon_index
    @last_icon_index = idx
    bmp = (idx >= 0 && idx < @icons.length) ? @icons[idx] : nil
    @sprites["icon_preview"].bitmap = bmp
  rescue
  end

  def dispose
    pbDisposeSpriteHash(@sprites) if @sprites
    @viewport.dispose if @viewport && !@viewport.disposed?
  rescue
  end
end

unless $BallSealsKIFLoaded
  $BallSealsKIFLoaded = true
  BallSealsKIF.init
end

#===============================================================================
# Icon Override - point to Graphics/BallSeals/
#===============================================================================
if defined?(GameData) && defined?(GameData::Item)
  class GameData::Item
    class << self
      alias ballseals_icon_original icon_filename
      def icon_filename(item)
        return ballseals_icon_original(item) if item.nil?
        item_data = self.try_get(item)
        if item_data && BallSealsKIF.all_seal_icon_files.key?(item_data.id)
          icon_file = BallSealsKIF.all_seal_icon_files[item_data.id]
          rel  = File.join(BallSealsKIF::ICONS_DIR, icon_file)
          # Use relative path — pbResolveBitmap and RGSS work with paths
          # relative to the game root; absolute paths break on most engines.
          return rel if pbResolveBitmap(rel)
          rel_noext = BallSealsKIF.strip_ext_for_rgss(rel)
          return rel_noext if pbResolveBitmap(rel_noext)
        end
        ballseals_icon_original(item)
      end
    end
  end
end
