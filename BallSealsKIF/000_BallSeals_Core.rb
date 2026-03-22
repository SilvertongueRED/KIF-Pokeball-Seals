# 000_BallSeals_Core.rb
$BallSealsKIFLoaded ||= false
module BallSealsKIF
  MOD_NAME = "BallSealsKIF"
  MOD_VERSION = "0.2.0-image-integration"
  LOG_PATH = File.join(Dir.pwd, "Mods", "BallSealsKIF.log") rescue "BallSealsKIF.log"
  MAX_CAPSULES = 12
  MAX_SEALS_PER_CAPSULE = 8
  FX_SCALE = 3.0
  CANVAS_ICON_SIZE = 20

  # ── Asset folder paths (relative to game root) ───────────────────
  GRAPHICS_BASE  = File.join("Graphics", "BallSeals")
  ICONS_DIR      = File.join(GRAPHICS_BASE, "Icons")
  ANIMATIONS_DIR = File.join(GRAPHICS_BASE, "Animations")
  GUI_DIR        = File.join(GRAPHICS_BASE, "GUI")

  # ── GUI image files (in GUI/ folder) ──────────────────────────────
  GUI_FILES = {
    :capsule_shape => "Pokeball.png",        # pokeball capsule overlay
    :capsule_bg    => "Display Boxes A.png", # seal case background
    :icon_strip    => "Palette.png",         # UI icon strip
    :side_panel    => "Display Boxes B.png", # info panel background
    :title_bar     => "Selector.png",        # header decoration bar
    :scroll_strip  => "Cursors.png"          # scroll indicator strip
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

  # ── Icon file mapping (Icons/ folder) ────────────────────────────
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

  # ── Animation file mapping (Animations/ folder) ──────────────────
  # Seals in the same group share the same animation particle sprite;
  # only the particle count varies between A/B/C… variants.
  SEAL_ANIM_FILES = {
    :HEART_A    => "Starburst Seal.png", :HEART_B    => "Starburst Seal.png",
    :HEART_C    => "Starburst Seal.png", :HEART_D    => "Starburst Seal.png",
    :HEART_E    => "Starburst Seal.png", :HEART_F    => "Starburst Seal.png",
    :STAR_A     => "Starburst Seal.png", :STAR_B     => "Starburst Seal.png",
    :STAR_C     => "Starburst Seal.png", :STAR_D     => "Starburst Seal.png",
    :STAR_E     => "Starburst Seal.png", :STAR_F     => "Starburst Seal.png",
    :LINE_A     => "Starburst Seal.png", :LINE_B     => "Starburst Seal.png",
    :LINE_C     => "Starburst Seal.png", :LINE_D     => "Starburst Seal.png",
    :SMOKE_A    => "Bubble Seal.png",    :SMOKE_B    => "Bubble Seal.png",
    :SMOKE_C    => "Bubble Seal.png",    :SMOKE_D    => "Bubble Seal.png",
    :SONG_A     => "Starburst Seal.png", :SONG_B     => "Starburst Seal.png",
    :SONG_C     => "Starburst Seal.png", :SONG_D     => "Starburst Seal.png",
    :SONG_E     => "Starburst Seal.png", :SONG_F     => "Starburst Seal.png",
    :SONG_G     => "Starburst Seal.png",
    :FIRE_A     => "Starburst Seal.png", :FIRE_B     => "Starburst Seal.png",
    :FIRE_C     => "Starburst Seal.png", :FIRE_D     => "Starburst Seal.png",
    :PARTY_A    => "Starburst Seal.png", :PARTY_B    => "Starburst Seal.png",
    :PARTY_C    => "Starburst Seal.png", :PARTY_D    => "Starburst Seal.png",
    :FLORA_A    => "Water Drop Seal.png",:FLORA_B    => "Water Drop Seal.png",
    :FLORA_C    => "Water Drop Seal.png",:FLORA_D    => "Water Drop Seal.png",
    :FLORA_E    => "Water Drop Seal.png",:FLORA_F    => "Water Drop Seal.png",
    :ELECTRIC_A => "Starburst Seal.png", :ELECTRIC_B => "Starburst Seal.png",
    :ELECTRIC_C => "Starburst Seal.png", :ELECTRIC_D => "Starburst Seal.png",
    :FOAMY_A    => "Bubble Seal.png",    :FOAMY_B    => "Bubble Seal.png",
    :FOAMY_C    => "Bubble Seal.png",    :FOAMY_D    => "Bubble Seal.png"
  }

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
    :ELE_E    => :ELECTRIC_D
  }

  @bitmaps ||= {}
  @active_fx ||= []
  @replacement_queue ||= []
  @graphics_hook_installed ||= false
  @menu_ensure_calls ||= 0

  # ── Helpers ───────────────────────────────────────────────────────

  # Strips image file extension so paths work with RGSS/MKXP Bitmap.new,
  # which auto-detects format and does not expect an extension in the path.
  def self.strip_ext_for_rgss(path)
    path.sub(/\.(png|bmp|jpg|jpeg|gif)$/i, "")
  end

  # Tries to load a Bitmap from path with its extension; if that fails,
  # retries with the extension stripped (for RGSS/MKXP compatibility).
  # Returns the Bitmap on success, or nil if both attempts fail.
  def self.load_bitmap_with_fallback(path)
    return nil if !path
    begin
      return Bitmap.new(path)
    rescue
    end
    noext = strip_ext_for_rgss(path)
    return nil if noext == path
    begin
      return Bitmap.new(noext)
    rescue
    end
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

  def self.seal_defs; SEAL_DEFS; end
  def self.seal_ids; SEAL_DEFS.map { |s| s[0] }; end

  def self.seal_name(sym)
    sym = resolve_seal_sym(sym)
    found = SEAL_DEFS.find { |s| s[0] == sym }
    return found ? found[1] : sym.to_s
  end

  def self.seal_style(sym)
    sym = resolve_seal_sym(sym)
    found = SEAL_DEFS.find { |s| s[0] == sym }
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
    SEAL_DEFS.each { |s| h[s[0]] = 99 }
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
          :x => 0.5 + Math.cos(ang) * 0.28,
          :y => 0.5 + Math.sin(ang) * 0.22
        }
      end
      return { :name => "Legacy", :placements => placements }
    end
    nil
  end

  def self.enqueue_capsule_for_pokemon(pkmn)
    cap = capsule_for_pokemon(pkmn)
    @replacement_queue << cap
  end

  def self.clear_replacement_queue; @replacement_queue = []; end
  def self.replacement_queue_pending?; !@replacement_queue.empty?; end
  def self.consume_replacement_capsule; @replacement_queue.empty? ? nil : @replacement_queue.shift; end

  # ── Asset path helpers ────────────────────────────────────────────

  def self.icon_path(sym)
    sym = resolve_seal_sym(sym)
    filename = SEAL_ICON_FILES[sym]
    return nil if !filename
    rel = File.join(ICONS_DIR, filename)
    abs = File.join(Dir.pwd, rel) rescue nil
    return abs if abs && File.exist?(abs)
    strip_ext_for_rgss(rel)
  end

  def self.animation_path(sym)
    sym = resolve_seal_sym(sym)
    filename = SEAL_ANIM_FILES[sym]
    return nil if !filename
    rel = File.join(ANIMATIONS_DIR, filename)
    abs = File.join(Dir.pwd, rel) rescue nil
    return abs if abs && File.exist?(abs)
    strip_ext_for_rgss(rel)
  end

  def self.gui_path(key)
    filename = GUI_FILES[key]
    return nil if !filename
    rel = File.join(GUI_DIR, filename)
    abs = File.join(Dir.pwd, rel) rescue nil
    return abs if abs && File.exist?(abs)
    strip_ext_for_rgss(rel)
  end

  # ── Bitmap loading ────────────────────────────────────────────────

  # Returns icon bitmap for menu/editor display (Icons/ folder).
  def self.bitmap_for(sym)
    sym = resolve_seal_sym(sym)
    return @bitmaps[sym] if @bitmaps[sym] && !@bitmaps[sym].disposed?
    bmp = load_bitmap_with_fallback(icon_path(sym))
    if bmp
      @bitmaps[sym] = bmp
      return @bitmaps[sym]
    end
    style = seal_style(sym)
    size = style[3] || 6
    bmp = Bitmap.new(size, size)
    c = style[2] || Color.new(255,255,255,220)
    bmp.fill_rect(0, 0, size, size, c)
    @bitmaps[sym] = bmp
    bmp
  end

  # Returns animation particle bitmap for pokeball burst (Animations/).
  # Falls back to the icon bitmap if no animation file is found.
  def self.animation_bitmap_for(sym)
    sym = resolve_seal_sym(sym)
    cache_key = :"anim_#{sym}"
    return @bitmaps[cache_key] if @bitmaps[cache_key] && !@bitmaps[cache_key].disposed?
    bmp = load_bitmap_with_fallback(animation_path(sym))
    if bmp
      @bitmaps[cache_key] = bmp
      return @bitmaps[cache_key]
    end
    bitmap_for(sym)
  end

  # Returns a GUI element bitmap (GUI/ folder).
  def self.gui_bitmap(key)
    cache_key = :"gui_#{key}"
    return @bitmaps[cache_key] if @bitmaps[cache_key] && !@bitmaps[cache_key].disposed?
    bmp = load_bitmap_with_fallback(gui_path(key))
    @bitmaps[cache_key] = bmp
    bmp
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

  def self.refresh_capsule_canvas(bitmap, cap, cursor_x = nil, cursor_y = nil)
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
    bitmap.fill_rect(bitmap.width/2 - 1, 18, 2, bitmap.height - 36, Color.new(120,140,160,100))
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
      c = Color.new(255,255,255)
      bitmap.fill_rect(px - 7, py, 15, 1, c)
      bitmap.fill_rect(px, py - 7, 1, 15, c)
      bitmap.fill_rect(px - 2, py - 2, 5, 5, Color.new(255,255,255,50))
    end
  end

  # ── Pokeball opening burst animation ──────────────────────────────

  def self.start_capsule_burst_on_viewport(viewport, x, y, cap)
    return if !cap || !cap[:placements] || cap[:placements].empty?
    return if !viewport || (viewport.respond_to?(:disposed?) && viewport.disposed?)
    particles = []
    cap[:placements].each do |pl|
      style = seal_style(pl[:seal])
      sym   = style[0]
      # Use animation sprite for the burst particles
      bmp   = animation_bitmap_for(sym)
      count = style[4] || 10
      grav  = style[5] || 0.12
      spin  = style[6] || 0.10
      ox = ((pl[:x].to_f - 0.5) * 72).to_i
      oy = ((pl[:y].to_f - 0.5) * 52).to_i
      [1, count / 2].max.times do
        sp = Sprite.new(viewport)
        sp.bitmap = bmp
        sp.ox = bmp.width / 2
        sp.oy = bmp.height / 2
        sp.x = x + ox + rand(-8..8)
        sp.y = y + oy + rand(-6..6)
        sp.z = 999999
        sp.opacity = 255
        sp.zoom_x = FX_SCALE
        sp.zoom_y = FX_SCALE
        vx = rand(-18..18) / 10.0
        vy = rand(-28..-6) / 10.0
        rot = rand(360)
        vr  = (rand(-10..10) / 10.0) + spin
        particles << [sp, vx, vy, grav, rot, vr]
      end
    end
    safe_play_se("Pkmn send out")
    @active_fx << { :vp => viewport, :frames => 32, :particles => particles }
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
    40.times do
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
    begin
      @menu_ensure_calls ||= 0
      @menu_ensure_calls += 1
      if @menu_ensure_calls > 3 && respond_to?(:ensure_menu_installed)
        ensure_menu_installed
      end
    rescue => e
      log("tick menu ensure ERROR: #{e.class}: #{e.message}")
    end
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
    ensure_global_data
    install_graphics_tick_hook
    log("=== #{MOD_NAME} #{MOD_VERSION} init ===")
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
    # Draw GUI title bar decoration across the top
    title_bmp = BallSealsKIF.gui_bitmap(:title_bar)
    if title_bmp
      dest = Rect.new(0, 0, Graphics.width, 38)
      src  = Rect.new(0, 0, title_bmp.width, title_bmp.height)
      @sprites["bg"].bitmap.stretch_blt(dest, title_bmp, src)
    end
    # Draw icon_strip as a thin decorative separator below the title area
    strip_bmp = BallSealsKIF.gui_bitmap(:icon_strip)
    if strip_bmp
      dest = Rect.new(0, 60, Graphics.width, 6)
      src  = Rect.new(0, 0, strip_bmp.width, strip_bmp.height)
      @sprites["bg"].bitmap.stretch_blt(dest, strip_bmp, src)
    end
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
    # Draw scroll_strip as a scroll indicator when the list overflows
    scroll_bmp = BallSealsKIF.gui_bitmap(:scroll_strip)
    visible_lines = [(win_h - 32) / line_h, 1].max
    if scroll_bmp && @commands.length > visible_lines
      scroll_x = x + win_w + 2
      scroll_h = [win_h, scroll_bmp.height].min
      dest = Rect.new(scroll_x, y, [scroll_bmp.width / 2, 16].min, scroll_h)
      src  = Rect.new(0, 0, scroll_bmp.width, scroll_bmp.height)
      @sprites["bg"].bitmap.stretch_blt(dest, scroll_bmp, src)
    end
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
      @sprites["icon_preview"].x = panel_x + (Graphics.width - panel_x) / 2 - 21
      @sprites["icon_preview"].y = panel_y + 16
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
