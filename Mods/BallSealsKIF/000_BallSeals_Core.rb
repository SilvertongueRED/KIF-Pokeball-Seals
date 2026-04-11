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
      :version => "0.4.0",
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
  MOD_VERSION = "0.4.0"
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
  # 140 seal types organized into 14 shape groups.
  # Each shape has 10 color variants labeled by color name:
  #   Black, Purple, Grey, Green, Yellow, Red, Pink, Orange, White, Blue
  SEAL_DEFS = [
    # Heart Seals (classic heart shape, 10 colors)
    [:HEART_BLACK,   "Heart Seal Black",   Color.new( 30, 30, 30,220),  6,  2, 0.18, 0.10],
    [:HEART_PURPLE,  "Heart Seal Purple",  Color.new(140, 40,180,220),  6,  4, 0.18, 0.10],
    [:HEART_GREY,    "Heart Seal Grey",    Color.new(150,150,150,220),  6,  6, 0.18, 0.10],
    [:HEART_GREEN,   "Heart Seal Green",   Color.new( 40,190, 60,220),  6,  8, 0.18, 0.10],
    [:HEART_YELLOW,  "Heart Seal Yellow",  Color.new(255,220, 30,220),  6, 10, 0.18, 0.10],
    [:HEART_RED,     "Heart Seal Red",     Color.new(230, 40, 40,220),  6, 12, 0.18, 0.10],
    [:HEART_PINK,    "Heart Seal Pink",    Color.new(255,120,180,220),  6, 14, 0.18, 0.10],
    [:HEART_ORANGE,  "Heart Seal Orange",  Color.new(255,160, 30,220),  6, 16, 0.18, 0.10],
    [:HEART_WHITE,   "Heart Seal White",   Color.new(240,240,240,220),  6, 18, 0.18, 0.10],
    [:HEART_BLUE,    "Heart Seal Blue",    Color.new( 50,120,240,220),  6, 20, 0.18, 0.10],
    # Star Seals (5-point star shape, 10 colors)
    [:STAR_BLACK,    "Star Seal Black",    Color.new( 30, 30, 30,220),  6,  2, 0.16, 0.20],
    [:STAR_PURPLE,   "Star Seal Purple",   Color.new(140, 40,180,220),  6,  4, 0.16, 0.20],
    [:STAR_GREY,     "Star Seal Grey",     Color.new(150,150,150,220),  6,  6, 0.16, 0.20],
    [:STAR_GREEN,    "Star Seal Green",    Color.new( 40,190, 60,220),  6,  8, 0.16, 0.20],
    [:STAR_YELLOW,   "Star Seal Yellow",   Color.new(255,220, 30,220),  6, 10, 0.16, 0.20],
    [:STAR_RED,      "Star Seal Red",      Color.new(230, 40, 40,220),  6, 12, 0.16, 0.20],
    [:STAR_PINK,     "Star Seal Pink",     Color.new(255,120,180,220),  6, 14, 0.16, 0.20],
    [:STAR_ORANGE,   "Star Seal Orange",   Color.new(255,160, 30,220),  6, 16, 0.16, 0.20],
    [:STAR_WHITE,    "Star Seal White",    Color.new(240,240,240,220),  6, 18, 0.16, 0.20],
    [:STAR_BLUE,     "Star Seal Blue",     Color.new( 50,120,240,220),  6, 20, 0.16, 0.20],
    # Smoke Seals (smoke puff shape, 10 colors)
    [:SMOKE_BLACK,   "Smoke Seal Black",   Color.new( 30, 30, 30,170),  8,  2,-0.02, 0.02],
    [:SMOKE_PURPLE,  "Smoke Seal Purple",  Color.new(140, 40,180,170),  8,  4,-0.02, 0.02],
    [:SMOKE_GREY,    "Smoke Seal Grey",    Color.new(150,150,150,170),  8,  6,-0.02, 0.02],
    [:SMOKE_GREEN,   "Smoke Seal Green",   Color.new( 40,190, 60,170),  8,  8,-0.02, 0.02],
    [:SMOKE_YELLOW,  "Smoke Seal Yellow",  Color.new(255,220, 30,170),  8, 10,-0.02, 0.02],
    [:SMOKE_RED,     "Smoke Seal Red",     Color.new(230, 40, 40,170),  8, 12,-0.02, 0.02],
    [:SMOKE_PINK,    "Smoke Seal Pink",    Color.new(255,120,180,170),  8, 14,-0.02, 0.02],
    [:SMOKE_ORANGE,  "Smoke Seal Orange",  Color.new(255,160, 30,170),  8, 16,-0.02, 0.02],
    [:SMOKE_WHITE,   "Smoke Seal White",   Color.new(240,240,240,170),  8, 18,-0.02, 0.02],
    [:SMOKE_BLUE,    "Smoke Seal Blue",    Color.new( 50,120,240,170),  8, 20,-0.02, 0.02],
    # Song Seals (music note shape, 10 colors)
    [:SONG_BLACK,    "Song Seal Black",    Color.new( 30, 30, 30,220),  6,  2, 0.10, 0.08],
    [:SONG_PURPLE,   "Song Seal Purple",   Color.new(140, 40,180,220),  6,  4, 0.10, 0.08],
    [:SONG_GREY,     "Song Seal Grey",     Color.new(150,150,150,220),  6,  6, 0.10, 0.08],
    [:SONG_GREEN,    "Song Seal Green",    Color.new( 40,190, 60,220),  6,  8, 0.10, 0.08],
    [:SONG_YELLOW,   "Song Seal Yellow",   Color.new(255,220, 30,220),  6, 10, 0.10, 0.08],
    [:SONG_RED,      "Song Seal Red",      Color.new(230, 40, 40,220),  6, 12, 0.10, 0.08],
    [:SONG_PINK,     "Song Seal Pink",     Color.new(255,120,180,220),  6, 14, 0.10, 0.08],
    [:SONG_ORANGE,   "Song Seal Orange",   Color.new(255,160, 30,220),  6, 16, 0.10, 0.08],
    [:SONG_WHITE,    "Song Seal White",    Color.new(240,240,240,220),  6, 18, 0.10, 0.08],
    [:SONG_BLUE,     "Song Seal Blue",     Color.new( 50,120,240,220),  6, 20, 0.10, 0.08],
    # Fire Seals (flame shape with center shading, 10 colors)
    [:FIRE_BLACK,    "Fire Seal Black",    Color.new( 30, 30, 30,220),  6,  2, 0.22, 0.08],
    [:FIRE_PURPLE,   "Fire Seal Purple",   Color.new(140, 40,180,220),  6,  4, 0.22, 0.08],
    [:FIRE_GREY,     "Fire Seal Grey",     Color.new(150,150,150,220),  6,  6, 0.22, 0.08],
    [:FIRE_GREEN,    "Fire Seal Green",    Color.new( 40,190, 60,220),  6,  8, 0.22, 0.08],
    [:FIRE_YELLOW,   "Fire Seal Yellow",   Color.new(255,220, 30,220),  6, 10, 0.22, 0.08],
    [:FIRE_RED,      "Fire Seal Red",      Color.new(230, 40, 40,220),  6, 12, 0.22, 0.08],
    [:FIRE_PINK,     "Fire Seal Pink",     Color.new(255,120,180,220),  6, 14, 0.22, 0.08],
    [:FIRE_ORANGE,   "Fire Seal Orange",   Color.new(255,160, 30,220),  6, 16, 0.22, 0.08],
    [:FIRE_WHITE,    "Fire Seal White",    Color.new(240,240,240,220),  6, 18, 0.22, 0.08],
    [:FIRE_BLUE,     "Fire Seal Blue",     Color.new( 50,120,240,220),  6, 20, 0.22, 0.08],
    # Sparkle Seals (diamond/sparkle shape, 10 colors)
    [:SPARKLE_BLACK,   "Sparkle Seal Black",   Color.new( 30, 30, 30,220),  4,  2, 0.18, 0.24],
    [:SPARKLE_PURPLE,  "Sparkle Seal Purple",  Color.new(140, 40,180,220),  4,  4, 0.18, 0.24],
    [:SPARKLE_GREY,    "Sparkle Seal Grey",    Color.new(150,150,150,220),  4,  6, 0.18, 0.24],
    [:SPARKLE_GREEN,   "Sparkle Seal Green",   Color.new( 40,190, 60,220),  4,  8, 0.18, 0.24],
    [:SPARKLE_YELLOW,  "Sparkle Seal Yellow",  Color.new(255,220, 30,220),  4, 10, 0.18, 0.24],
    [:SPARKLE_RED,     "Sparkle Seal Red",     Color.new(230, 40, 40,220),  4, 12, 0.18, 0.24],
    [:SPARKLE_PINK,    "Sparkle Seal Pink",    Color.new(255,120,180,220),  4, 14, 0.18, 0.24],
    [:SPARKLE_ORANGE,  "Sparkle Seal Orange",  Color.new(255,160, 30,220),  4, 16, 0.18, 0.24],
    [:SPARKLE_WHITE,   "Sparkle Seal White",   Color.new(240,240,240,220),  4, 18, 0.18, 0.24],
    [:SPARKLE_BLUE,    "Sparkle Seal Blue",    Color.new( 50,120,240,220),  4, 20, 0.18, 0.24],
    # Flower Seals (flower with center circle, 10 colors — renamed from Flora)
    [:FLOWER_BLACK,  "Flower Seal Black",  Color.new( 30, 30, 30,220),  6,  2, 0.14, 0.12],
    [:FLOWER_PURPLE, "Flower Seal Purple", Color.new(140, 40,180,220),  6,  4, 0.14, 0.12],
    [:FLOWER_GREY,   "Flower Seal Grey",   Color.new(150,150,150,220),  6,  6, 0.14, 0.12],
    [:FLOWER_GREEN,  "Flower Seal Green",  Color.new( 40,190, 60,220),  6,  8, 0.14, 0.12],
    [:FLOWER_YELLOW, "Flower Seal Yellow", Color.new(255,220, 30,220),  6, 10, 0.14, 0.12],
    [:FLOWER_RED,    "Flower Seal Red",    Color.new(230, 40, 40,220),  6, 12, 0.14, 0.12],
    [:FLOWER_PINK,   "Flower Seal Pink",   Color.new(255,120,180,220),  6, 14, 0.14, 0.12],
    [:FLOWER_ORANGE, "Flower Seal Orange", Color.new(255,160, 30,220),  6, 16, 0.14, 0.12],
    [:FLOWER_WHITE,  "Flower Seal White",  Color.new(240,240,240,220),  6, 18, 0.14, 0.12],
    [:FLOWER_BLUE,   "Flower Seal Blue",   Color.new( 50,120,240,220),  6, 20, 0.14, 0.12],
    # Electric Seals (lightning bolt shape, 10 colors)
    [:ELECTRIC_BLACK,  "Electric Seal Black",  Color.new( 30, 30, 30,230),  4,  2, 0.10, 0.28],
    [:ELECTRIC_PURPLE, "Electric Seal Purple", Color.new(140, 40,180,230),  4,  4, 0.10, 0.28],
    [:ELECTRIC_GREY,   "Electric Seal Grey",   Color.new(150,150,150,230),  4,  6, 0.10, 0.28],
    [:ELECTRIC_GREEN,  "Electric Seal Green",  Color.new( 40,190, 60,230),  4,  8, 0.10, 0.28],
    [:ELECTRIC_YELLOW, "Electric Seal Yellow", Color.new(255,220, 30,230),  4, 10, 0.10, 0.28],
    [:ELECTRIC_RED,    "Electric Seal Red",    Color.new(230, 40, 40,230),  4, 12, 0.10, 0.28],
    [:ELECTRIC_PINK,   "Electric Seal Pink",   Color.new(255,120,180,230),  4, 14, 0.10, 0.28],
    [:ELECTRIC_ORANGE, "Electric Seal Orange", Color.new(255,160, 30,230),  4, 16, 0.10, 0.28],
    [:ELECTRIC_WHITE,  "Electric Seal White",  Color.new(240,240,240,230),  4, 18, 0.10, 0.28],
    [:ELECTRIC_BLUE,   "Electric Seal Blue",   Color.new( 50,120,240,230),  4, 20, 0.10, 0.28],
    # Bubble Seals (circle with inner highlight, 10 colors — renamed from Foamy)
    [:BUBBLE_BLACK,  "Bubble Seal Black",  Color.new( 30, 30, 30,180),  7,  2,-0.03, 0.04],
    [:BUBBLE_PURPLE, "Bubble Seal Purple", Color.new(140, 40,180,180),  7,  4,-0.03, 0.04],
    [:BUBBLE_GREY,   "Bubble Seal Grey",   Color.new(150,150,150,180),  7,  6,-0.03, 0.04],
    [:BUBBLE_GREEN,  "Bubble Seal Green",  Color.new( 40,190, 60,180),  7,  8,-0.03, 0.04],
    [:BUBBLE_YELLOW, "Bubble Seal Yellow", Color.new(255,220, 30,180),  7, 10,-0.03, 0.04],
    [:BUBBLE_RED,    "Bubble Seal Red",    Color.new(230, 40, 40,180),  7, 12,-0.03, 0.04],
    [:BUBBLE_PINK,   "Bubble Seal Pink",   Color.new(255,120,180,180),  7, 14,-0.03, 0.04],
    [:BUBBLE_ORANGE, "Bubble Seal Orange", Color.new(255,160, 30,180),  7, 16,-0.03, 0.04],
    [:BUBBLE_WHITE,  "Bubble Seal White",  Color.new(240,240,240,180),  7, 18,-0.03, 0.04],
    [:BUBBLE_BLUE,   "Bubble Seal Blue",   Color.new( 50,120,240,180),  7, 20,-0.03, 0.04],
    # Skull Seals (pixelated skull shape, 10 colors)
    [:SKULL_BLACK,   "Skull Seal Black",   Color.new( 30, 30, 30,220),  6,  2, 0.14, 0.06],
    [:SKULL_PURPLE,  "Skull Seal Purple",  Color.new(140, 40,180,220),  6,  4, 0.14, 0.06],
    [:SKULL_GREY,    "Skull Seal Grey",    Color.new(150,150,150,220),  6,  6, 0.14, 0.06],
    [:SKULL_GREEN,   "Skull Seal Green",   Color.new( 40,190, 60,220),  6,  8, 0.14, 0.06],
    [:SKULL_YELLOW,  "Skull Seal Yellow",  Color.new(255,220, 30,220),  6, 10, 0.14, 0.06],
    [:SKULL_RED,     "Skull Seal Red",     Color.new(230, 40, 40,220),  6, 12, 0.14, 0.06],
    [:SKULL_PINK,    "Skull Seal Pink",    Color.new(255,120,180,220),  6, 14, 0.14, 0.06],
    [:SKULL_ORANGE,  "Skull Seal Orange",  Color.new(255,160, 30,220),  6, 16, 0.14, 0.06],
    [:SKULL_WHITE,   "Skull Seal White",   Color.new(240,240,240,220),  6, 18, 0.14, 0.06],
    [:SKULL_BLUE,    "Skull Seal Blue",    Color.new( 50,120,240,220),  6, 20, 0.14, 0.06],
    # Bat Seals (bat shape with vertical eyes, 10 colors)
    [:BAT_BLACK,     "Bat Seal Black",     Color.new( 30, 30, 30,220),  6,  2, 0.16, 0.10],
    [:BAT_PURPLE,    "Bat Seal Purple",    Color.new(140, 40,180,220),  6,  4, 0.16, 0.10],
    [:BAT_GREY,      "Bat Seal Grey",      Color.new(150,150,150,220),  6,  6, 0.16, 0.10],
    [:BAT_GREEN,     "Bat Seal Green",     Color.new( 40,190, 60,220),  6,  8, 0.16, 0.10],
    [:BAT_YELLOW,    "Bat Seal Yellow",    Color.new(255,220, 30,220),  6, 10, 0.16, 0.10],
    [:BAT_RED,       "Bat Seal Red",       Color.new(230, 40, 40,220),  6, 12, 0.16, 0.10],
    [:BAT_PINK,      "Bat Seal Pink",      Color.new(255,120,180,220),  6, 14, 0.16, 0.10],
    [:BAT_ORANGE,    "Bat Seal Orange",    Color.new(255,160, 30,220),  6, 16, 0.16, 0.10],
    [:BAT_WHITE,     "Bat Seal White",     Color.new(240,240,240,220),  6, 18, 0.16, 0.10],
    [:BAT_BLUE,      "Bat Seal Blue",      Color.new( 50,120,240,220),  6, 20, 0.16, 0.10],
    # Tombstone Seals (tombstone shape, 10 colors — new)
    [:TOMBSTONE_BLACK,   "Tombstone Seal Black",   Color.new( 30, 30, 30,220),  6,  2, 0.14, 0.06],
    [:TOMBSTONE_PURPLE,  "Tombstone Seal Purple",  Color.new(140, 40,180,220),  6,  4, 0.14, 0.06],
    [:TOMBSTONE_GREY,    "Tombstone Seal Grey",    Color.new(150,150,150,220),  6,  6, 0.14, 0.06],
    [:TOMBSTONE_GREEN,   "Tombstone Seal Green",   Color.new( 40,190, 60,220),  6,  8, 0.14, 0.06],
    [:TOMBSTONE_YELLOW,  "Tombstone Seal Yellow",  Color.new(255,220, 30,220),  6, 10, 0.14, 0.06],
    [:TOMBSTONE_RED,     "Tombstone Seal Red",     Color.new(230, 40, 40,220),  6, 12, 0.14, 0.06],
    [:TOMBSTONE_PINK,    "Tombstone Seal Pink",    Color.new(255,120,180,220),  6, 14, 0.14, 0.06],
    [:TOMBSTONE_ORANGE,  "Tombstone Seal Orange",  Color.new(255,160, 30,220),  6, 16, 0.14, 0.06],
    [:TOMBSTONE_WHITE,   "Tombstone Seal White",   Color.new(240,240,240,220),  6, 18, 0.14, 0.06],
    [:TOMBSTONE_BLUE,    "Tombstone Seal Blue",    Color.new( 50,120,240,220),  6, 20, 0.14, 0.06],
    # Coffin Seals (coffin shape, 10 colors — new)
    [:COFFIN_BLACK,   "Coffin Seal Black",   Color.new( 30, 30, 30,220),  6,  2, 0.14, 0.06],
    [:COFFIN_PURPLE,  "Coffin Seal Purple",  Color.new(140, 40,180,220),  6,  4, 0.14, 0.06],
    [:COFFIN_GREY,    "Coffin Seal Grey",    Color.new(150,150,150,220),  6,  6, 0.14, 0.06],
    [:COFFIN_GREEN,   "Coffin Seal Green",   Color.new( 40,190, 60,220),  6,  8, 0.14, 0.06],
    [:COFFIN_YELLOW,  "Coffin Seal Yellow",  Color.new(255,220, 30,220),  6, 10, 0.14, 0.06],
    [:COFFIN_RED,     "Coffin Seal Red",     Color.new(230, 40, 40,220),  6, 12, 0.14, 0.06],
    [:COFFIN_PINK,    "Coffin Seal Pink",    Color.new(255,120,180,220),  6, 14, 0.14, 0.06],
    [:COFFIN_ORANGE,  "Coffin Seal Orange",  Color.new(255,160, 30,220),  6, 16, 0.14, 0.06],
    [:COFFIN_WHITE,   "Coffin Seal White",   Color.new(240,240,240,220),  6, 18, 0.14, 0.06],
    [:COFFIN_BLUE,    "Coffin Seal Blue",    Color.new( 50,120,240,220),  6, 20, 0.14, 0.06],
  ]

  # ── Icon file mapping (Icons/ folder — used for both GUI and battle) ─
  SEAL_ICON_FILES = {
    :HEART_BLACK    => "Heart Seal Black.png",    :HEART_PURPLE   => "Heart Seal Purple.png",
    :HEART_GREY     => "Heart Seal Grey.png",     :HEART_GREEN    => "Heart Seal Green.png",
    :HEART_YELLOW   => "Heart Seal Yellow.png",   :HEART_RED      => "Heart Seal Red.png",
    :HEART_PINK     => "Heart Seal Pink.png",     :HEART_ORANGE   => "Heart Seal Orange.png",
    :HEART_WHITE    => "Heart Seal White.png",    :HEART_BLUE     => "Heart Seal Blue.png",
    :STAR_BLACK     => "Star Seal Black.png",     :STAR_PURPLE    => "Star Seal Purple.png",
    :STAR_GREY      => "Star Seal Grey.png",      :STAR_GREEN     => "Star Seal Green.png",
    :STAR_YELLOW    => "Star Seal Yellow.png",    :STAR_RED       => "Star Seal Red.png",
    :STAR_PINK      => "Star Seal Pink.png",      :STAR_ORANGE    => "Star Seal Orange.png",
    :STAR_WHITE     => "Star Seal White.png",     :STAR_BLUE      => "Star Seal Blue.png",
    :SMOKE_BLACK    => "Smoke Seal Black.png",    :SMOKE_PURPLE   => "Smoke Seal Purple.png",
    :SMOKE_GREY     => "Smoke Seal Grey.png",     :SMOKE_GREEN    => "Smoke Seal Green.png",
    :SMOKE_YELLOW   => "Smoke Seal Yellow.png",   :SMOKE_RED      => "Smoke Seal Red.png",
    :SMOKE_PINK     => "Smoke Seal Pink.png",     :SMOKE_ORANGE   => "Smoke Seal Orange.png",
    :SMOKE_WHITE    => "Smoke Seal White.png",    :SMOKE_BLUE     => "Smoke Seal Blue.png",
    :SONG_BLACK     => "Song Seal Black.png",     :SONG_PURPLE    => "Song Seal Purple.png",
    :SONG_GREY      => "Song Seal Grey.png",      :SONG_GREEN     => "Song Seal Green.png",
    :SONG_YELLOW    => "Song Seal Yellow.png",    :SONG_RED       => "Song Seal Red.png",
    :SONG_PINK      => "Song Seal Pink.png",      :SONG_ORANGE    => "Song Seal Orange.png",
    :SONG_WHITE     => "Song Seal White.png",     :SONG_BLUE      => "Song Seal Blue.png",
    :FIRE_BLACK     => "Fire Seal Black.png",     :FIRE_PURPLE    => "Fire Seal Purple.png",
    :FIRE_GREY      => "Fire Seal Grey.png",      :FIRE_GREEN     => "Fire Seal Green.png",
    :FIRE_YELLOW    => "Fire Seal Yellow.png",    :FIRE_RED       => "Fire Seal Red.png",
    :FIRE_PINK      => "Fire Seal Pink.png",      :FIRE_ORANGE    => "Fire Seal Orange.png",
    :FIRE_WHITE     => "Fire Seal White.png",     :FIRE_BLUE      => "Fire Seal Blue.png",
    :SPARKLE_BLACK    => "Sparkle Seal Black.png",    :SPARKLE_PURPLE   => "Sparkle Seal Purple.png",
    :SPARKLE_GREY     => "Sparkle Seal Grey.png",     :SPARKLE_GREEN    => "Sparkle Seal Green.png",
    :SPARKLE_YELLOW   => "Sparkle Seal Yellow.png",   :SPARKLE_RED      => "Sparkle Seal Red.png",
    :SPARKLE_PINK     => "Sparkle Seal Pink.png",     :SPARKLE_ORANGE   => "Sparkle Seal Orange.png",
    :SPARKLE_WHITE    => "Sparkle Seal White.png",    :SPARKLE_BLUE     => "Sparkle Seal Blue.png",
    :FLOWER_BLACK   => "Flower Seal Black.png",   :FLOWER_PURPLE  => "Flower Seal Purple.png",
    :FLOWER_GREY    => "Flower Seal Grey.png",    :FLOWER_GREEN   => "Flower Seal Green.png",
    :FLOWER_YELLOW  => "Flower Seal Yellow.png",  :FLOWER_RED     => "Flower Seal Red.png",
    :FLOWER_PINK    => "Flower Seal Pink.png",    :FLOWER_ORANGE  => "Flower Seal Orange.png",
    :FLOWER_WHITE   => "Flower Seal White.png",   :FLOWER_BLUE    => "Flower Seal Blue.png",
    :ELECTRIC_BLACK => "Electric Seal Black.png", :ELECTRIC_PURPLE=> "Electric Seal Purple.png",
    :ELECTRIC_GREY  => "Electric Seal Grey.png",  :ELECTRIC_GREEN => "Electric Seal Green.png",
    :ELECTRIC_YELLOW=> "Electric Seal Yellow.png",:ELECTRIC_RED   => "Electric Seal Red.png",
    :ELECTRIC_PINK  => "Electric Seal Pink.png",  :ELECTRIC_ORANGE=> "Electric Seal Orange.png",
    :ELECTRIC_WHITE => "Electric Seal White.png", :ELECTRIC_BLUE  => "Electric Seal Blue.png",
    :BUBBLE_BLACK   => "Bubble Seal Black.png",   :BUBBLE_PURPLE  => "Bubble Seal Purple.png",
    :BUBBLE_GREY    => "Bubble Seal Grey.png",    :BUBBLE_GREEN   => "Bubble Seal Green.png",
    :BUBBLE_YELLOW  => "Bubble Seal Yellow.png",  :BUBBLE_RED     => "Bubble Seal Red.png",
    :BUBBLE_PINK    => "Bubble Seal Pink.png",    :BUBBLE_ORANGE  => "Bubble Seal Orange.png",
    :BUBBLE_WHITE   => "Bubble Seal White.png",   :BUBBLE_BLUE    => "Bubble Seal Blue.png",
    :SKULL_BLACK    => "Skull Seal Black.png",    :SKULL_PURPLE   => "Skull Seal Purple.png",
    :SKULL_GREY     => "Skull Seal Grey.png",     :SKULL_GREEN    => "Skull Seal Green.png",
    :SKULL_YELLOW   => "Skull Seal Yellow.png",   :SKULL_RED      => "Skull Seal Red.png",
    :SKULL_PINK     => "Skull Seal Pink.png",     :SKULL_ORANGE   => "Skull Seal Orange.png",
    :SKULL_WHITE    => "Skull Seal White.png",    :SKULL_BLUE     => "Skull Seal Blue.png",
    :BAT_BLACK      => "Bat Seal Black.png",      :BAT_PURPLE     => "Bat Seal Purple.png",
    :BAT_GREY       => "Bat Seal Grey.png",       :BAT_GREEN      => "Bat Seal Green.png",
    :BAT_YELLOW     => "Bat Seal Yellow.png",     :BAT_RED        => "Bat Seal Red.png",
    :BAT_PINK       => "Bat Seal Pink.png",       :BAT_ORANGE     => "Bat Seal Orange.png",
    :BAT_WHITE      => "Bat Seal White.png",      :BAT_BLUE       => "Bat Seal Blue.png",
    :TOMBSTONE_BLACK  => "Tombstone Seal Black.png",  :TOMBSTONE_PURPLE => "Tombstone Seal Purple.png",
    :TOMBSTONE_GREY   => "Tombstone Seal Grey.png",   :TOMBSTONE_GREEN  => "Tombstone Seal Green.png",
    :TOMBSTONE_YELLOW => "Tombstone Seal Yellow.png", :TOMBSTONE_RED    => "Tombstone Seal Red.png",
    :TOMBSTONE_PINK   => "Tombstone Seal Pink.png",   :TOMBSTONE_ORANGE => "Tombstone Seal Orange.png",
    :TOMBSTONE_WHITE  => "Tombstone Seal White.png",  :TOMBSTONE_BLUE   => "Tombstone Seal Blue.png",
    :COFFIN_BLACK   => "Coffin Seal Black.png",   :COFFIN_PURPLE  => "Coffin Seal Purple.png",
    :COFFIN_GREY    => "Coffin Seal Grey.png",    :COFFIN_GREEN   => "Coffin Seal Green.png",
    :COFFIN_YELLOW  => "Coffin Seal Yellow.png",  :COFFIN_RED     => "Coffin Seal Red.png",
    :COFFIN_PINK    => "Coffin Seal Pink.png",    :COFFIN_ORANGE  => "Coffin Seal Orange.png",
    :COFFIN_WHITE   => "Coffin Seal White.png",   :COFFIN_BLUE    => "Coffin Seal Blue.png"
  }

  # NOTE: The Animations/ folder has been merged into Icons/.  Battle
  # burst particles now use the same images shown in the GUI/editor.

  # ── Legacy seal symbol mapping (backward compat with older saves) ─
  LEGACY_SEAL_MAP = {
    # Original single-seal names
    :HEART    => :HEART_BLACK,
    :STAR     => :STAR_BLACK,
    :BUBBLE   => :BUBBLE_BLACK,
    :SPARK    => :ELECTRIC_BLACK,
    :SMOKE    => :SMOKE_BLACK,
    :NOTE     => :SONG_BLACK,
    :FLOWER   => :FLOWER_BLACK,
    :LEAF     => :FLOWER_PURPLE,
    :SNOW     => :BUBBLE_PURPLE,
    :FIRE     => :FIRE_BLACK,
    :RING     => :ELECTRIC_PURPLE,
    :DROPLET  => :BUBBLE_GREY,
    :CONFETTI => :SPARKLE_BLACK,
    :BEAM     => :ELECTRIC_GREY,
    :CLOUD    => :SMOKE_PURPLE,
    :FLASH    => :ELECTRIC_GREY,
    :SKULL    => :SKULL_BLACK,
    :BAT      => :BAT_BLACK,
    # Old ELE_* prefix (pre-rename)
    :ELE_A    => :ELECTRIC_BLACK,
    :ELE_B    => :ELECTRIC_PURPLE,
    :ELE_C    => :ELECTRIC_GREY,
    :ELE_D    => :ELECTRIC_GREEN,
    :ELE_E    => :ELECTRIC_GREEN,
    # Old letter-suffixed symbols → new color-suffixed symbols
    :HEART_A  => :HEART_BLACK,    :HEART_B  => :HEART_PURPLE,
    :HEART_C  => :HEART_GREY,     :HEART_D  => :HEART_GREEN,
    :HEART_E  => :HEART_YELLOW,   :HEART_F  => :HEART_RED,
    :HEART_G  => :HEART_PINK,     :HEART_H  => :HEART_ORANGE,
    :HEART_I  => :HEART_WHITE,    :HEART_J  => :HEART_BLUE,
    :STAR_A   => :STAR_BLACK,     :STAR_B   => :STAR_PURPLE,
    :STAR_C   => :STAR_GREY,      :STAR_D   => :STAR_GREEN,
    :STAR_E   => :STAR_YELLOW,    :STAR_F   => :STAR_RED,
    :STAR_G   => :STAR_PINK,      :STAR_H   => :STAR_ORANGE,
    :STAR_I   => :STAR_WHITE,     :STAR_J   => :STAR_BLUE,
    :LINE_A   => :SMOKE_BLACK,    :LINE_B   => :SMOKE_PURPLE,
    :LINE_C   => :SMOKE_GREY,     :LINE_D   => :SMOKE_GREEN,
    :LINE_E   => :SMOKE_YELLOW,   :LINE_F   => :SMOKE_RED,
    :LINE_G   => :SMOKE_PINK,     :LINE_H   => :SMOKE_ORANGE,
    :LINE_I   => :SMOKE_WHITE,    :LINE_J   => :SMOKE_BLUE,
    :SMOKE_A  => :SMOKE_BLACK,    :SMOKE_B  => :SMOKE_PURPLE,
    :SMOKE_C  => :SMOKE_GREY,     :SMOKE_D  => :SMOKE_GREEN,
    :SMOKE_E  => :SMOKE_YELLOW,   :SMOKE_F  => :SMOKE_RED,
    :SMOKE_G  => :SMOKE_PINK,     :SMOKE_H  => :SMOKE_ORANGE,
    :SMOKE_I  => :SMOKE_WHITE,    :SMOKE_J  => :SMOKE_BLUE,
    :SONG_A   => :SONG_BLACK,     :SONG_B   => :SONG_PURPLE,
    :SONG_C   => :SONG_GREY,      :SONG_D   => :SONG_GREEN,
    :SONG_E   => :SONG_YELLOW,    :SONG_F   => :SONG_RED,
    :SONG_G   => :SONG_PINK,      :SONG_H   => :SONG_ORANGE,
    :SONG_I   => :SONG_WHITE,     :SONG_J   => :SONG_BLUE,
    :FIRE_A   => :FIRE_BLACK,     :FIRE_B   => :FIRE_PURPLE,
    :FIRE_C   => :FIRE_GREY,      :FIRE_D   => :FIRE_GREEN,
    :FIRE_E   => :FIRE_YELLOW,    :FIRE_F   => :FIRE_RED,
    :FIRE_G   => :FIRE_PINK,      :FIRE_H   => :FIRE_ORANGE,
    :FIRE_I   => :FIRE_WHITE,     :FIRE_J   => :FIRE_BLUE,
    :PARTY_A  => :SPARKLE_BLACK,    :PARTY_B  => :SPARKLE_PURPLE,
    :PARTY_C  => :SPARKLE_GREY,     :PARTY_D  => :SPARKLE_GREEN,
    :PARTY_E  => :SPARKLE_YELLOW,   :PARTY_F  => :SPARKLE_RED,
    :PARTY_G  => :SPARKLE_PINK,     :PARTY_H  => :SPARKLE_ORANGE,
    :PARTY_I  => :SPARKLE_WHITE,    :PARTY_J  => :SPARKLE_BLUE,
    # Old Party_* symbols (pre-Sparkle rename)
    :PARTY_BLACK   => :SPARKLE_BLACK,   :PARTY_PURPLE  => :SPARKLE_PURPLE,
    :PARTY_GREY    => :SPARKLE_GREY,    :PARTY_GREEN   => :SPARKLE_GREEN,
    :PARTY_YELLOW  => :SPARKLE_YELLOW,  :PARTY_RED     => :SPARKLE_RED,
    :PARTY_PINK    => :SPARKLE_PINK,    :PARTY_ORANGE  => :SPARKLE_ORANGE,
    :PARTY_WHITE   => :SPARKLE_WHITE,   :PARTY_BLUE    => :SPARKLE_BLUE,
    :FLORA_A  => :FLOWER_BLACK,   :FLORA_B  => :FLOWER_PURPLE,
    :FLORA_C  => :FLOWER_GREY,    :FLORA_D  => :FLOWER_GREEN,
    :FLORA_E  => :FLOWER_YELLOW,  :FLORA_F  => :FLOWER_RED,
    :FLORA_G  => :FLOWER_PINK,    :FLORA_H  => :FLOWER_ORANGE,
    :FLORA_I  => :FLOWER_WHITE,   :FLORA_J  => :FLOWER_BLUE,
    :ELECTRIC_A => :ELECTRIC_BLACK,  :ELECTRIC_B => :ELECTRIC_PURPLE,
    :ELECTRIC_C => :ELECTRIC_GREY,   :ELECTRIC_D => :ELECTRIC_GREEN,
    :ELECTRIC_E => :ELECTRIC_YELLOW, :ELECTRIC_F => :ELECTRIC_RED,
    :ELECTRIC_G => :ELECTRIC_PINK,   :ELECTRIC_H => :ELECTRIC_ORANGE,
    :ELECTRIC_I => :ELECTRIC_WHITE,  :ELECTRIC_J => :ELECTRIC_BLUE,
    :FOAMY_A  => :BUBBLE_BLACK,   :FOAMY_B  => :BUBBLE_PURPLE,
    :FOAMY_C  => :BUBBLE_GREY,    :FOAMY_D  => :BUBBLE_GREEN,
    :FOAMY_E  => :BUBBLE_YELLOW,  :FOAMY_F  => :BUBBLE_RED,
    :FOAMY_G  => :BUBBLE_PINK,    :FOAMY_H  => :BUBBLE_ORANGE,
    :FOAMY_I  => :BUBBLE_WHITE,   :FOAMY_J  => :BUBBLE_BLUE,
    :SKULL_A  => :SKULL_BLACK,    :SKULL_B  => :SKULL_PURPLE,
    :SKULL_C  => :SKULL_GREY,     :SKULL_D  => :SKULL_GREEN,
    :SKULL_E  => :SKULL_YELLOW,   :SKULL_F  => :SKULL_RED,
    :SKULL_G  => :SKULL_PINK,     :SKULL_H  => :SKULL_ORANGE,
    :SKULL_I  => :SKULL_WHITE,    :SKULL_J  => :SKULL_BLUE,
    :BAT_A    => :BAT_BLACK,      :BAT_B    => :BAT_PURPLE,
    :BAT_C    => :BAT_GREY,       :BAT_D    => :BAT_GREEN,
    :BAT_E    => :BAT_YELLOW,     :BAT_F    => :BAT_RED,
    :BAT_G    => :BAT_PINK,       :BAT_H    => :BAT_ORANGE,
    :BAT_I    => :BAT_WHITE,      :BAT_J    => :BAT_BLUE,
    # Old Fist_* symbols (removed — map to Star seals as closest visual match)
    :FIST_BLACK   => :STAR_BLACK,   :FIST_PURPLE  => :STAR_PURPLE,
    :FIST_GREY    => :STAR_GREY,    :FIST_GREEN   => :STAR_GREEN,
    :FIST_YELLOW  => :STAR_YELLOW,  :FIST_RED     => :STAR_RED,
    :FIST_PINK    => :STAR_PINK,    :FIST_ORANGE  => :STAR_ORANGE,
    :FIST_WHITE   => :STAR_WHITE,   :FIST_BLUE    => :STAR_BLUE
  }

  @bitmaps ||= {}
  @active_fx ||= []
  @replacement_queue ||= []
  @graphics_hook_installed ||= false
  @menu_ensure_calls ||= 0
  @dynamic_seal_defs ||= []
  @dynamic_seal_icon_files ||= {}
  @seal_overlay_vp = nil

  # ── Seal overlay viewport ──────────────────────────────────────────
  # A dedicated full-screen viewport with a very high z-value so seal
  # animations always render on top of Pokémon sprites, regardless of
  # which viewport the battler sprite lives on (EBDX, Ghost Classic+,
  # vanilla Essentials, etc.).  Created lazily on first use and disposed
  # automatically once all active effects have finished.
  SEAL_OVERLAY_Z = 99999

  def self.seal_overlay_viewport
    if @seal_overlay_vp && !@seal_overlay_vp.disposed?
      return @seal_overlay_vp
    end
    @seal_overlay_vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @seal_overlay_vp.z = SEAL_OVERLAY_Z
    @seal_overlay_vp
  rescue => e
    log("seal_overlay_viewport ERROR: #{e.class}: #{e.message}")
    # Fallback: try once more without caching
    Viewport.new(0, 0, Graphics.width, Graphics.height)
  end

  def self.dispose_seal_overlay_viewport
    if @seal_overlay_vp && !@seal_overlay_vp.disposed?
      @seal_overlay_vp.dispose
    end
    @seal_overlay_vp = nil
  rescue => e
    log("dispose_seal_overlay_viewport ERROR: #{e.class}: #{e.message}")
    @seal_overlay_vp = nil
  end

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
  # images (e.g. letter seals A-Z) to be used in-game simply by dropping
  # them into the Icons/ folder.
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

  def self.clear_replacement_queue
    @replacement_queue = []
    @ebdx_ball_index = 0
  end
  def self.replacement_queue_pending?; !@replacement_queue.empty?; end
  def self.consume_replacement_capsule
    return nil if @replacement_queue.empty?
    entry = @replacement_queue.shift
    # Support both old (bare capsule) and new (hash with :cap/:idx_battler) formats
    result = entry.is_a?(Hash) && entry.key?(:cap) ? entry : { :cap => entry, :idx_battler => nil }
    # Track ball order for staggered animation timing in EBDX
    result[:ball_index] = @ebdx_ball_index || 0
    @ebdx_ball_index = (@ebdx_ball_index || 0) + 1
    result
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
    # Vertical center line: offset 1.0% right of true center (was 1.5%, shifted left 0.5%)
    vert_x = (bitmap.width / 2.0 + bitmap.width * 0.010).to_i - 1
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
  # 50 frames = 2.5 seconds at 20fps for better timing alignment
  # with Ghost's ball-open animation.
  GHOST_BURST_DELAY = 50

  # Per-pokeball stagger delay (in frames) when multiple pokeballs
  # open at once (e.g. doubles/triples).  The first pokeball's seals
  # play immediately; each subsequent pokeball is delayed by this
  # many additional frames so they animate sequentially.
  # 20 frames ≈ 1 second at 20fps — enough separation to be visible.
  MULTI_BALL_STAGGER = 20

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
    # Use a dedicated overlay viewport so seal sprites always render on
    # top of Pokémon sprites regardless of which viewport the battler
    # is drawn on (EBDX, Ghost Classic+, vanilla Essentials, etc.).
    # The caller's viewport is only used as a liveness check — if it is
    # disposed the battle scene is gone and we should not draw anything.
    if viewport && viewport.respond_to?(:disposed?) && viewport.disposed?
      return
    end
    overlay = seal_overlay_viewport
    return if !overlay || (overlay.respond_to?(:disposed?) && overlay.disposed?)
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
      sp = Sprite.new(overlay)
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
      @active_fx << { :vp => overlay, :frames => 38, :delay => burst_delay,
                      :hold => 40, :started => started, :particles => particles }
      # Make visible immediately only when there is no burst delay
      if started
        particles.each { |p| p[0].opacity = 255 if p[0] && !p[0].disposed? }
      end
    end
    safe_play_se("Pkmn send out")
    log("DBG: Started capsule burst with #{cap[:placements].length} placements at (#{x},#{y}) on overlay viewport z=#{SEAL_OVERLAY_Z}")
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
    # When all seal effects have finished, dispose the overlay viewport
    # so it does not linger and interfere with other scenes.
    dispose_seal_overlay_viewport if keep.empty?
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
