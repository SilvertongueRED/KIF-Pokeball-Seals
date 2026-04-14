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
      :version => "0.8.0",
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
  MOD_VERSION = "0.8.0"
  LOG_PATH = File.join(Dir.pwd, "Mods", "BallSealsKIF.log") rescue "BallSealsKIF.log"
  MAX_CAPSULES = 12
  MAX_SEALS_PER_CAPSULE = 10
  FX_SCALE = 3.0
  CANVAS_ICON_SIZE = 20
  # Rightward offset (as a fraction of canvas width) applied to the
  # placement grid so that x=0.5 lands on the pokeball's visual centre.
  GRID_X_OFFSET = 0.025

  # ── Seal list sorting ────────────────────────────────────────────
  # Persists for the session (across menu openings) but resets on
  # game restart.  :alpha = alphabetical, :recent = recently used first.
  @seal_sort_mode = :alpha
  def self.seal_sort_mode; @seal_sort_mode; end
  def self.seal_sort_mode=(v); @seal_sort_mode = v; end

  # ── Animation group sorting ────────────────────────────────────
  # Same session-persistent sort for the Animations menu.
  # :alpha = alphabetical by group name, :recent = recently changed first.
  @anim_sort_mode = :alpha
  def self.anim_sort_mode; @anim_sort_mode; end
  def self.anim_sort_mode=(v); @anim_sort_mode = v; end

  # ── Animation types ──────────────────────────────────────────────
  # Available animation styles for seal burst effects.  Each capsule
  # stores per-group overrides in :anim_settings; missing keys fall
  # back to DEFAULT_ANIM_SETTINGS.
  ANIM_TYPES = [:static, :sparkle, :throb, :rolling, :wiggle, :staggered,
                :big_loud, :explode, :slam, :swirl, :puff]
  ANIM_TYPE_NAMES = {
    :static    => "Static",
    :sparkle   => "Sparkle",
    :throb     => "Throb",
    :rolling   => "Rolling",
    :wiggle    => "Wiggle",
    :staggered => "Staggered",
    :big_loud  => "Big/Loud",
    :explode   => "Explode",
    :slam      => "Slam",
    :swirl     => "Swirl",
    :puff      => "Puff"
  }

  # Seal groups for animation assignment.  Each capsule can have a
  # different animation type per seal type group.  Every shape and
  # Pokémon-type family is its own group so users can mix-and-match
  # animations freely.
  ANIM_GROUPS = [
    # Shape seal groups
    :heart, :star, :smoke, :song, :fire, :sparkle_seal, :flower,
    :electric, :bubble, :skull, :bat, :tombstone, :coffin,
    # Pokémon type seal groups
    :normal, :fighting, :flying, :poison, :ground, :rock,
    :bug, :ghost_seal, :steel, :water, :grass, :psychic,
    :ice, :dragon, :dark, :fairy,
    # Letter / punctuation seals
    :letter
  ]
  ANIM_GROUP_NAMES = {
    :heart        => "Heart Seals",
    :star         => "Star Seals",
    :smoke        => "Smoke Seals",
    :song         => "Song Seals",
    :fire         => "Fire Seals",
    :sparkle_seal => "Sparkle Seals",
    :flower       => "Flower Seals",
    :electric     => "Electric Seals",
    :bubble       => "Bubble Seals",
    :skull        => "Skull Seals",
    :bat          => "Bat Seals",
    :tombstone    => "Tombstone Seals",
    :coffin       => "Coffin Seals",
    :normal       => "Normal Type Seals",
    :fighting     => "Fighting Type Seals",
    :flying       => "Flying Type Seals",
    :poison       => "Poison Type Seals",
    :ground       => "Ground Type Seals",
    :rock         => "Rock Type Seals",
    :bug          => "Bug Type Seals",
    :ghost_seal   => "Ghost Type Seals",
    :steel        => "Steel Type Seals",
    :water        => "Water Type Seals",
    :grass        => "Grass Type Seals",
    :psychic      => "Psychic Type Seals",
    :ice          => "Ice Type Seals",
    :dragon       => "Dragon Type Seals",
    :dark         => "Dark Type Seals",
    :fairy        => "Fairy Type Seals",
    :letter       => "Letter Seals"
  }
  DEFAULT_ANIM_SETTINGS = {
    :heart        => :throb,
    :star         => :static,
    :smoke        => :static,
    :song         => :static,
    :fire         => :static,
    :sparkle_seal => :sparkle,
    :flower       => :static,
    :electric     => :static,
    :bubble       => :static,
    :skull        => :static,
    :bat          => :static,
    :tombstone    => :static,
    :coffin       => :static,
    :normal       => :static,
    :fighting     => :static,
    :flying       => :static,
    :poison       => :static,
    :ground       => :static,
    :rock         => :static,
    :bug          => :static,
    :ghost_seal   => :static,
    :steel        => :static,
    :water        => :static,
    :grass        => :static,
    :psychic      => :static,
    :ice          => :static,
    :dragon       => :static,
    :dark         => :static,
    :fairy        => :static,
    :letter       => :static
  }

  # Maps old animation group keys to their new equivalents so that
  # existing save data that used the old :sparkle or :other keys is
  # resolved correctly after the groups were expanded.
  LEGACY_ANIM_GROUP_MAP = {
    :sparkle => :sparkle_seal,
    :other   => nil   # handled as fallback in capsule_anim_type
  }

  # ── Multi-pokémon dimming ────────────────────────────────────────
  # When multiple pokémon are sent out (doubles/triples), previously
  # released pokémon's seal effects are dimmed to this opacity while
  # a newer pokémon's seals are actively animating (hold phase).
  MULTI_DIM_OPACITY = 100

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
  # 283 seal types organized into 14 shape groups + 16 Pokémon type groups.
  # Each shape has 10 color variants labeled by color name:
  #   Black, Purple, Grey, Green, Yellow, Red, Pink, Orange, White, Blue
  # (Rock type seals have 3 variants: Black, Brown, Grey)
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
    # ── Pokémon Type Seals ─────────────────────────────────────────
    # Normal Seals (normal-type icon, 10 colors)
    [:NORMAL_SEAL_BLACK,   "Normal Seal Black",   Color.new( 30, 30, 30,220),  6,  2, 0.12, 0.06],
    [:NORMAL_SEAL_PURPLE,  "Normal Seal Purple",  Color.new(140, 40,180,220),  6,  4, 0.12, 0.06],
    [:NORMAL_SEAL_GREY,    "Normal Seal Grey",    Color.new(150,150,150,220),  6,  6, 0.12, 0.06],
    [:NORMAL_SEAL_GREEN,   "Normal Seal Green",   Color.new( 40,190, 60,220),  6,  8, 0.12, 0.06],
    [:NORMAL_SEAL_YELLOW,  "Normal Seal Yellow",  Color.new(255,220, 30,220),  6, 10, 0.12, 0.06],
    [:NORMAL_SEAL_RED,     "Normal Seal Red",     Color.new(230, 40, 40,220),  6, 12, 0.12, 0.06],
    [:NORMAL_SEAL_PINK,    "Normal Seal Pink",    Color.new(255,120,180,220),  6, 14, 0.12, 0.06],
    [:NORMAL_SEAL_ORANGE,  "Normal Seal Orange",  Color.new(255,160, 30,220),  6, 16, 0.12, 0.06],
    [:NORMAL_SEAL_WHITE,   "Normal Seal White",   Color.new(240,240,240,220),  6, 18, 0.12, 0.06],
    [:NORMAL_SEAL_BLUE,    "Normal Seal Blue",    Color.new( 50,120,240,220),  6, 20, 0.12, 0.06],
    # Fighting Seals (fighting-type icon, 10 colors)
    [:FIGHTING_SEAL_BLACK,   "Fighting Seal Black",   Color.new( 30, 30, 30,220),  6,  2, 0.14, 0.08],
    [:FIGHTING_SEAL_PURPLE,  "Fighting Seal Purple",  Color.new(140, 40,180,220),  6,  4, 0.14, 0.08],
    [:FIGHTING_SEAL_GREY,    "Fighting Seal Grey",    Color.new(150,150,150,220),  6,  6, 0.14, 0.08],
    [:FIGHTING_SEAL_GREEN,   "Fighting Seal Green",   Color.new( 40,190, 60,220),  6,  8, 0.14, 0.08],
    [:FIGHTING_SEAL_YELLOW,  "Fighting Seal Yellow",  Color.new(255,220, 30,220),  6, 10, 0.14, 0.08],
    [:FIGHTING_SEAL_RED,     "Fighting Seal Red",     Color.new(230, 40, 40,220),  6, 12, 0.14, 0.08],
    [:FIGHTING_SEAL_PINK,    "Fighting Seal Pink",    Color.new(255,120,180,220),  6, 14, 0.14, 0.08],
    [:FIGHTING_SEAL_ORANGE,  "Fighting Seal Orange",  Color.new(255,160, 30,220),  6, 16, 0.14, 0.08],
    [:FIGHTING_SEAL_WHITE,   "Fighting Seal White",   Color.new(240,240,240,220),  6, 18, 0.14, 0.08],
    [:FIGHTING_SEAL_BLUE,    "Fighting Seal Blue",    Color.new( 50,120,240,220),  6, 20, 0.14, 0.08],
    # Flying Seals (flying-type icon, 10 colors)
    [:FLYING_SEAL_BLACK,   "Flying Seal Black",   Color.new( 30, 30, 30,220),  6,  2, 0.10, 0.14],
    [:FLYING_SEAL_PURPLE,  "Flying Seal Purple",  Color.new(140, 40,180,220),  6,  4, 0.10, 0.14],
    [:FLYING_SEAL_GREY,    "Flying Seal Grey",    Color.new(150,150,150,220),  6,  6, 0.10, 0.14],
    [:FLYING_SEAL_GREEN,   "Flying Seal Green",   Color.new( 40,190, 60,220),  6,  8, 0.10, 0.14],
    [:FLYING_SEAL_YELLOW,  "Flying Seal Yellow",  Color.new(255,220, 30,220),  6, 10, 0.10, 0.14],
    [:FLYING_SEAL_RED,     "Flying Seal Red",     Color.new(230, 40, 40,220),  6, 12, 0.10, 0.14],
    [:FLYING_SEAL_PINK,    "Flying Seal Pink",    Color.new(255,120,180,220),  6, 14, 0.10, 0.14],
    [:FLYING_SEAL_ORANGE,  "Flying Seal Orange",  Color.new(255,160, 30,220),  6, 16, 0.10, 0.14],
    [:FLYING_SEAL_WHITE,   "Flying Seal White",   Color.new(240,240,240,220),  6, 18, 0.10, 0.14],
    [:FLYING_SEAL_BLUE,    "Flying Seal Blue",    Color.new( 50,120,240,220),  6, 20, 0.10, 0.14],
    # Poison Seals (poison-type icon, 10 colors)
    [:POISON_SEAL_BLACK,   "Poison Seal Black",   Color.new( 30, 30, 30,220),  6,  2, 0.14, 0.06],
    [:POISON_SEAL_PURPLE,  "Poison Seal Purple",  Color.new(140, 40,180,220),  6,  4, 0.14, 0.06],
    [:POISON_SEAL_GREY,    "Poison Seal Grey",    Color.new(150,150,150,220),  6,  6, 0.14, 0.06],
    [:POISON_SEAL_GREEN,   "Poison Seal Green",   Color.new( 40,190, 60,220),  6,  8, 0.14, 0.06],
    [:POISON_SEAL_YELLOW,  "Poison Seal Yellow",  Color.new(255,220, 30,220),  6, 10, 0.14, 0.06],
    [:POISON_SEAL_RED,     "Poison Seal Red",     Color.new(230, 40, 40,220),  6, 12, 0.14, 0.06],
    [:POISON_SEAL_PINK,    "Poison Seal Pink",    Color.new(255,120,180,220),  6, 14, 0.14, 0.06],
    [:POISON_SEAL_ORANGE,  "Poison Seal Orange",  Color.new(255,160, 30,220),  6, 16, 0.14, 0.06],
    [:POISON_SEAL_WHITE,   "Poison Seal White",   Color.new(240,240,240,220),  6, 18, 0.14, 0.06],
    [:POISON_SEAL_BLUE,    "Poison Seal Blue",    Color.new( 50,120,240,220),  6, 20, 0.14, 0.06],
    # Ground Seals (ground-type icon, 10 colors)
    [:GROUND_SEAL_BLACK,   "Ground Seal Black",   Color.new( 30, 30, 30,220),  6,  2, 0.16, 0.04],
    [:GROUND_SEAL_PURPLE,  "Ground Seal Purple",  Color.new(140, 40,180,220),  6,  4, 0.16, 0.04],
    [:GROUND_SEAL_GREY,    "Ground Seal Grey",    Color.new(150,150,150,220),  6,  6, 0.16, 0.04],
    [:GROUND_SEAL_GREEN,   "Ground Seal Green",   Color.new( 40,190, 60,220),  6,  8, 0.16, 0.04],
    [:GROUND_SEAL_YELLOW,  "Ground Seal Yellow",  Color.new(255,220, 30,220),  6, 10, 0.16, 0.04],
    [:GROUND_SEAL_RED,     "Ground Seal Red",     Color.new(230, 40, 40,220),  6, 12, 0.16, 0.04],
    [:GROUND_SEAL_PINK,    "Ground Seal Pink",    Color.new(255,120,180,220),  6, 14, 0.16, 0.04],
    [:GROUND_SEAL_ORANGE,  "Ground Seal Orange",  Color.new(255,160, 30,220),  6, 16, 0.16, 0.04],
    [:GROUND_SEAL_WHITE,   "Ground Seal White",   Color.new(240,240,240,220),  6, 18, 0.16, 0.04],
    [:GROUND_SEAL_BLUE,    "Ground Seal Blue",    Color.new( 50,120,240,220),  6, 20, 0.16, 0.04],
    # Rock Seals (rock-type icon, 3 colors)
    [:ROCK_SEAL_BLACK,  "Rock Seal Black",  Color.new( 30, 30, 30,220),  6,  2, 0.18, 0.04],
    [:ROCK_SEAL_BROWN,  "Rock Seal Brown",  Color.new(160,110, 50,220),  6,  4, 0.18, 0.04],
    [:ROCK_SEAL_GREY,   "Rock Seal Grey",   Color.new(150,150,150,220),  6,  6, 0.18, 0.04],
    # Bug Seals (bug-type icon, 10 colors)
    [:BUG_SEAL_BLACK,   "Bug Seal Black",   Color.new( 30, 30, 30,220),  6,  2, 0.12, 0.10],
    [:BUG_SEAL_PURPLE,  "Bug Seal Purple",  Color.new(140, 40,180,220),  6,  4, 0.12, 0.10],
    [:BUG_SEAL_GREY,    "Bug Seal Grey",    Color.new(150,150,150,220),  6,  6, 0.12, 0.10],
    [:BUG_SEAL_GREEN,   "Bug Seal Green",   Color.new( 40,190, 60,220),  6,  8, 0.12, 0.10],
    [:BUG_SEAL_YELLOW,  "Bug Seal Yellow",  Color.new(255,220, 30,220),  6, 10, 0.12, 0.10],
    [:BUG_SEAL_RED,     "Bug Seal Red",     Color.new(230, 40, 40,220),  6, 12, 0.12, 0.10],
    [:BUG_SEAL_PINK,    "Bug Seal Pink",    Color.new(255,120,180,220),  6, 14, 0.12, 0.10],
    [:BUG_SEAL_ORANGE,  "Bug Seal Orange",  Color.new(255,160, 30,220),  6, 16, 0.12, 0.10],
    [:BUG_SEAL_WHITE,   "Bug Seal White",   Color.new(240,240,240,220),  6, 18, 0.12, 0.10],
    [:BUG_SEAL_BLUE,    "Bug Seal Blue",    Color.new( 50,120,240,220),  6, 20, 0.12, 0.10],
    # Ghost Seals (ghost-type icon, 10 colors)
    [:GHOST_SEAL_BLACK,   "Ghost Seal Black",   Color.new( 30, 30, 30,220),  6,  2, 0.10, 0.08],
    [:GHOST_SEAL_PURPLE,  "Ghost Seal Purple",  Color.new(140, 40,180,220),  6,  4, 0.10, 0.08],
    [:GHOST_SEAL_GREY,    "Ghost Seal Grey",    Color.new(150,150,150,220),  6,  6, 0.10, 0.08],
    [:GHOST_SEAL_GREEN,   "Ghost Seal Green",   Color.new( 40,190, 60,220),  6,  8, 0.10, 0.08],
    [:GHOST_SEAL_YELLOW,  "Ghost Seal Yellow",  Color.new(255,220, 30,220),  6, 10, 0.10, 0.08],
    [:GHOST_SEAL_RED,     "Ghost Seal Red",     Color.new(230, 40, 40,220),  6, 12, 0.10, 0.08],
    [:GHOST_SEAL_PINK,    "Ghost Seal Pink",    Color.new(255,120,180,220),  6, 14, 0.10, 0.08],
    [:GHOST_SEAL_ORANGE,  "Ghost Seal Orange",  Color.new(255,160, 30,220),  6, 16, 0.10, 0.08],
    [:GHOST_SEAL_WHITE,   "Ghost Seal White",   Color.new(240,240,240,220),  6, 18, 0.10, 0.08],
    [:GHOST_SEAL_BLUE,    "Ghost Seal Blue",    Color.new( 50,120,240,220),  6, 20, 0.10, 0.08],
    # Steel Seals (steel-type icon, 10 colors)
    [:STEEL_SEAL_BLACK,   "Steel Seal Black",   Color.new( 30, 30, 30,220),  6,  2, 0.16, 0.06],
    [:STEEL_SEAL_PURPLE,  "Steel Seal Purple",  Color.new(140, 40,180,220),  6,  4, 0.16, 0.06],
    [:STEEL_SEAL_GREY,    "Steel Seal Grey",    Color.new(150,150,150,220),  6,  6, 0.16, 0.06],
    [:STEEL_SEAL_GREEN,   "Steel Seal Green",   Color.new( 40,190, 60,220),  6,  8, 0.16, 0.06],
    [:STEEL_SEAL_YELLOW,  "Steel Seal Yellow",  Color.new(255,220, 30,220),  6, 10, 0.16, 0.06],
    [:STEEL_SEAL_RED,     "Steel Seal Red",     Color.new(230, 40, 40,220),  6, 12, 0.16, 0.06],
    [:STEEL_SEAL_PINK,    "Steel Seal Pink",    Color.new(255,120,180,220),  6, 14, 0.16, 0.06],
    [:STEEL_SEAL_ORANGE,  "Steel Seal Orange",  Color.new(255,160, 30,220),  6, 16, 0.16, 0.06],
    [:STEEL_SEAL_WHITE,   "Steel Seal White",   Color.new(240,240,240,220),  6, 18, 0.16, 0.06],
    [:STEEL_SEAL_BLUE,    "Steel Seal Blue",    Color.new( 50,120,240,220),  6, 20, 0.16, 0.06],
    # Water Seals (water-type icon, 10 colors)
    [:WATER_SEAL_BLACK,   "Water Seal Black",   Color.new( 30, 30, 30,220),  6,  2, 0.12, 0.08],
    [:WATER_SEAL_PURPLE,  "Water Seal Purple",  Color.new(140, 40,180,220),  6,  4, 0.12, 0.08],
    [:WATER_SEAL_GREY,    "Water Seal Grey",    Color.new(150,150,150,220),  6,  6, 0.12, 0.08],
    [:WATER_SEAL_GREEN,   "Water Seal Green",   Color.new( 40,190, 60,220),  6,  8, 0.12, 0.08],
    [:WATER_SEAL_YELLOW,  "Water Seal Yellow",  Color.new(255,220, 30,220),  6, 10, 0.12, 0.08],
    [:WATER_SEAL_RED,     "Water Seal Red",     Color.new(230, 40, 40,220),  6, 12, 0.12, 0.08],
    [:WATER_SEAL_PINK,    "Water Seal Pink",    Color.new(255,120,180,220),  6, 14, 0.12, 0.08],
    [:WATER_SEAL_ORANGE,  "Water Seal Orange",  Color.new(255,160, 30,220),  6, 16, 0.12, 0.08],
    [:WATER_SEAL_WHITE,   "Water Seal White",   Color.new(240,240,240,220),  6, 18, 0.12, 0.08],
    [:WATER_SEAL_BLUE,    "Water Seal Blue",    Color.new( 50,120,240,220),  6, 20, 0.12, 0.08],
    # Grass Seals (grass-type icon, 10 colors)
    [:GRASS_SEAL_BLACK,   "Grass Seal Black",   Color.new( 30, 30, 30,220),  6,  2, 0.12, 0.10],
    [:GRASS_SEAL_PURPLE,  "Grass Seal Purple",  Color.new(140, 40,180,220),  6,  4, 0.12, 0.10],
    [:GRASS_SEAL_GREY,    "Grass Seal Grey",    Color.new(150,150,150,220),  6,  6, 0.12, 0.10],
    [:GRASS_SEAL_GREEN,   "Grass Seal Green",   Color.new( 40,190, 60,220),  6,  8, 0.12, 0.10],
    [:GRASS_SEAL_YELLOW,  "Grass Seal Yellow",  Color.new(255,220, 30,220),  6, 10, 0.12, 0.10],
    [:GRASS_SEAL_RED,     "Grass Seal Red",     Color.new(230, 40, 40,220),  6, 12, 0.12, 0.10],
    [:GRASS_SEAL_PINK,    "Grass Seal Pink",    Color.new(255,120,180,220),  6, 14, 0.12, 0.10],
    [:GRASS_SEAL_ORANGE,  "Grass Seal Orange",  Color.new(255,160, 30,220),  6, 16, 0.12, 0.10],
    [:GRASS_SEAL_WHITE,   "Grass Seal White",   Color.new(240,240,240,220),  6, 18, 0.12, 0.10],
    [:GRASS_SEAL_BLUE,    "Grass Seal Blue",    Color.new( 50,120,240,220),  6, 20, 0.12, 0.10],
    # Psychic Seals (psychic-type icon, 10 colors)
    [:PSYCHIC_SEAL_BLACK,   "Psychic Seal Black",   Color.new( 30, 30, 30,220),  6,  2, 0.10, 0.12],
    [:PSYCHIC_SEAL_PURPLE,  "Psychic Seal Purple",  Color.new(140, 40,180,220),  6,  4, 0.10, 0.12],
    [:PSYCHIC_SEAL_GREY,    "Psychic Seal Grey",    Color.new(150,150,150,220),  6,  6, 0.10, 0.12],
    [:PSYCHIC_SEAL_GREEN,   "Psychic Seal Green",   Color.new( 40,190, 60,220),  6,  8, 0.10, 0.12],
    [:PSYCHIC_SEAL_YELLOW,  "Psychic Seal Yellow",  Color.new(255,220, 30,220),  6, 10, 0.10, 0.12],
    [:PSYCHIC_SEAL_RED,     "Psychic Seal Red",     Color.new(230, 40, 40,220),  6, 12, 0.10, 0.12],
    [:PSYCHIC_SEAL_PINK,    "Psychic Seal Pink",    Color.new(255,120,180,220),  6, 14, 0.10, 0.12],
    [:PSYCHIC_SEAL_ORANGE,  "Psychic Seal Orange",  Color.new(255,160, 30,220),  6, 16, 0.10, 0.12],
    [:PSYCHIC_SEAL_WHITE,   "Psychic Seal White",   Color.new(240,240,240,220),  6, 18, 0.10, 0.12],
    [:PSYCHIC_SEAL_BLUE,    "Psychic Seal Blue",    Color.new( 50,120,240,220),  6, 20, 0.10, 0.12],
    # Ice Seals (ice-type icon, 10 colors)
    [:ICE_SEAL_BLACK,   "Ice Seal Black",   Color.new( 30, 30, 30,220),  6,  2, 0.08, 0.14],
    [:ICE_SEAL_PURPLE,  "Ice Seal Purple",  Color.new(140, 40,180,220),  6,  4, 0.08, 0.14],
    [:ICE_SEAL_GREY,    "Ice Seal Grey",    Color.new(150,150,150,220),  6,  6, 0.08, 0.14],
    [:ICE_SEAL_GREEN,   "Ice Seal Green",   Color.new( 40,190, 60,220),  6,  8, 0.08, 0.14],
    [:ICE_SEAL_YELLOW,  "Ice Seal Yellow",  Color.new(255,220, 30,220),  6, 10, 0.08, 0.14],
    [:ICE_SEAL_RED,     "Ice Seal Red",     Color.new(230, 40, 40,220),  6, 12, 0.08, 0.14],
    [:ICE_SEAL_PINK,    "Ice Seal Pink",    Color.new(255,120,180,220),  6, 14, 0.08, 0.14],
    [:ICE_SEAL_ORANGE,  "Ice Seal Orange",  Color.new(255,160, 30,220),  6, 16, 0.08, 0.14],
    [:ICE_SEAL_WHITE,   "Ice Seal White",   Color.new(240,240,240,220),  6, 18, 0.08, 0.14],
    [:ICE_SEAL_BLUE,    "Ice Seal Blue",    Color.new( 50,120,240,220),  6, 20, 0.08, 0.14],
    # Dragon Seals (dragon-type icon, 10 colors)
    [:DRAGON_SEAL_BLACK,   "Dragon Seal Black",   Color.new( 30, 30, 30,220),  6,  2, 0.14, 0.10],
    [:DRAGON_SEAL_PURPLE,  "Dragon Seal Purple",  Color.new(140, 40,180,220),  6,  4, 0.14, 0.10],
    [:DRAGON_SEAL_GREY,    "Dragon Seal Grey",    Color.new(150,150,150,220),  6,  6, 0.14, 0.10],
    [:DRAGON_SEAL_GREEN,   "Dragon Seal Green",   Color.new( 40,190, 60,220),  6,  8, 0.14, 0.10],
    [:DRAGON_SEAL_YELLOW,  "Dragon Seal Yellow",  Color.new(255,220, 30,220),  6, 10, 0.14, 0.10],
    [:DRAGON_SEAL_RED,     "Dragon Seal Red",     Color.new(230, 40, 40,220),  6, 12, 0.14, 0.10],
    [:DRAGON_SEAL_PINK,    "Dragon Seal Pink",    Color.new(255,120,180,220),  6, 14, 0.14, 0.10],
    [:DRAGON_SEAL_ORANGE,  "Dragon Seal Orange",  Color.new(255,160, 30,220),  6, 16, 0.14, 0.10],
    [:DRAGON_SEAL_WHITE,   "Dragon Seal White",   Color.new(240,240,240,220),  6, 18, 0.14, 0.10],
    [:DRAGON_SEAL_BLUE,    "Dragon Seal Blue",    Color.new( 50,120,240,220),  6, 20, 0.14, 0.10],
    # Dark Seals (dark-type icon, 10 colors)
    [:DARK_SEAL_BLACK,   "Dark Seal Black",   Color.new( 30, 30, 30,220),  6,  2, 0.14, 0.06],
    [:DARK_SEAL_PURPLE,  "Dark Seal Purple",  Color.new(140, 40,180,220),  6,  4, 0.14, 0.06],
    [:DARK_SEAL_GREY,    "Dark Seal Grey",    Color.new(150,150,150,220),  6,  6, 0.14, 0.06],
    [:DARK_SEAL_GREEN,   "Dark Seal Green",   Color.new( 40,190, 60,220),  6,  8, 0.14, 0.06],
    [:DARK_SEAL_YELLOW,  "Dark Seal Yellow",  Color.new(255,220, 30,220),  6, 10, 0.14, 0.06],
    [:DARK_SEAL_RED,     "Dark Seal Red",     Color.new(230, 40, 40,220),  6, 12, 0.14, 0.06],
    [:DARK_SEAL_PINK,    "Dark Seal Pink",    Color.new(255,120,180,220),  6, 14, 0.14, 0.06],
    [:DARK_SEAL_ORANGE,  "Dark Seal Orange",  Color.new(255,160, 30,220),  6, 16, 0.14, 0.06],
    [:DARK_SEAL_WHITE,   "Dark Seal White",   Color.new(240,240,240,220),  6, 18, 0.14, 0.06],
    [:DARK_SEAL_BLUE,    "Dark Seal Blue",    Color.new( 50,120,240,220),  6, 20, 0.14, 0.06],
    # Fairy Seals (fairy-type icon, 10 colors)
    [:FAIRY_SEAL_BLACK,   "Fairy Seal Black",   Color.new( 30, 30, 30,220),  6,  2, 0.10, 0.12],
    [:FAIRY_SEAL_PURPLE,  "Fairy Seal Purple",  Color.new(140, 40,180,220),  6,  4, 0.10, 0.12],
    [:FAIRY_SEAL_GREY,    "Fairy Seal Grey",    Color.new(150,150,150,220),  6,  6, 0.10, 0.12],
    [:FAIRY_SEAL_GREEN,   "Fairy Seal Green",   Color.new( 40,190, 60,220),  6,  8, 0.10, 0.12],
    [:FAIRY_SEAL_YELLOW,  "Fairy Seal Yellow",  Color.new(255,220, 30,220),  6, 10, 0.10, 0.12],
    [:FAIRY_SEAL_RED,     "Fairy Seal Red",     Color.new(230, 40, 40,220),  6, 12, 0.10, 0.12],
    [:FAIRY_SEAL_PINK,    "Fairy Seal Pink",    Color.new(255,120,180,220),  6, 14, 0.10, 0.12],
    [:FAIRY_SEAL_ORANGE,  "Fairy Seal Orange",  Color.new(255,160, 30,220),  6, 16, 0.10, 0.12],
    [:FAIRY_SEAL_WHITE,   "Fairy Seal White",   Color.new(240,240,240,220),  6, 18, 0.10, 0.12],
    [:FAIRY_SEAL_BLUE,    "Fairy Seal Blue",    Color.new( 50,120,240,220),  6, 20, 0.10, 0.12],
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
    :COFFIN_WHITE   => "Coffin Seal White.png",   :COFFIN_BLUE    => "Coffin Seal Blue.png",
    # ── Pokémon Type Seals ─────────────────────────────────────────
    :NORMAL_SEAL_BLACK   => "Normal Seal Black.png",   :NORMAL_SEAL_PURPLE  => "Normal Seal Purple.png",
    :NORMAL_SEAL_GREY    => "Normal Seal Grey.png",    :NORMAL_SEAL_GREEN   => "Normal Seal Green.png",
    :NORMAL_SEAL_YELLOW  => "Normal Seal Yellow.png",  :NORMAL_SEAL_RED     => "Normal Seal Red.png",
    :NORMAL_SEAL_PINK    => "Normal Seal Pink.png",    :NORMAL_SEAL_ORANGE  => "Normal Seal Orange.png",
    :NORMAL_SEAL_WHITE   => "Normal Seal White.png",   :NORMAL_SEAL_BLUE    => "Normal Seal Blue.png",
    :FIGHTING_SEAL_BLACK   => "Fighting Seal Black.png",   :FIGHTING_SEAL_PURPLE  => "Fighting Seal Purple.png",
    :FIGHTING_SEAL_GREY    => "Fighting Seal Grey.png",    :FIGHTING_SEAL_GREEN   => "Fighting Seal Green.png",
    :FIGHTING_SEAL_YELLOW  => "Fighting Seal Yellow.png",  :FIGHTING_SEAL_RED     => "Fighting Seal Red.png",
    :FIGHTING_SEAL_PINK    => "Fighting Seal Pink.png",    :FIGHTING_SEAL_ORANGE  => "Fighting Seal Orange.png",
    :FIGHTING_SEAL_WHITE   => "Fighting Seal White.png",   :FIGHTING_SEAL_BLUE    => "Fighting Seal Blue.png",
    :FLYING_SEAL_BLACK   => "Flying Seal Black.png",   :FLYING_SEAL_PURPLE  => "Flying Seal Purple.png",
    :FLYING_SEAL_GREY    => "Flying Seal Grey.png",    :FLYING_SEAL_GREEN   => "Flying Seal Green.png",
    :FLYING_SEAL_YELLOW  => "Flying Seal Yellow.png",  :FLYING_SEAL_RED     => "Flying Seal Red.png",
    :FLYING_SEAL_PINK    => "Flying Seal Pink.png",    :FLYING_SEAL_ORANGE  => "Flying Seal Orange.png",
    :FLYING_SEAL_WHITE   => "Flying Seal White.png",   :FLYING_SEAL_BLUE    => "Flying Seal Blue.png",
    :POISON_SEAL_BLACK   => "Poison Seal Black.png",   :POISON_SEAL_PURPLE  => "Poison Seal Purple.png",
    :POISON_SEAL_GREY    => "Poison Seal Grey.png",    :POISON_SEAL_GREEN   => "Poison Seal Green.png",
    :POISON_SEAL_YELLOW  => "Poison Seal Yellow.png",  :POISON_SEAL_RED     => "Poison Seal Red.png",
    :POISON_SEAL_PINK    => "Poison Seal Pink.png",    :POISON_SEAL_ORANGE  => "Poison Seal Orange.png",
    :POISON_SEAL_WHITE   => "Poison Seal White.png",   :POISON_SEAL_BLUE    => "Poison Seal Blue.png",
    :GROUND_SEAL_BLACK   => "Ground Seal Black.png",   :GROUND_SEAL_PURPLE  => "Ground Seal Purple.png",
    :GROUND_SEAL_GREY    => "Ground Seal Grey.png",    :GROUND_SEAL_GREEN   => "Ground Seal Green.png",
    :GROUND_SEAL_YELLOW  => "Ground Seal Yellow.png",  :GROUND_SEAL_RED     => "Ground Seal Red.png",
    :GROUND_SEAL_PINK    => "Ground Seal Pink.png",    :GROUND_SEAL_ORANGE  => "Ground Seal Orange.png",
    :GROUND_SEAL_WHITE   => "Ground Seal White.png",   :GROUND_SEAL_BLUE    => "Ground Seal Blue.png",
    :ROCK_SEAL_BLACK  => "Rock Seal Black.png",
    :ROCK_SEAL_BROWN  => "Rock Seal Brown.png",
    :ROCK_SEAL_GREY   => "Rock Seal Grey.png",
    :BUG_SEAL_BLACK   => "Bug Seal Black.png",   :BUG_SEAL_PURPLE  => "Bug Seal Purple.png",
    :BUG_SEAL_GREY    => "Bug Seal Grey.png",    :BUG_SEAL_GREEN   => "Bug Seal Green.png",
    :BUG_SEAL_YELLOW  => "Bug Seal Yellow.png",  :BUG_SEAL_RED     => "Bug Seal Red.png",
    :BUG_SEAL_PINK    => "Bug Seal Pink.png",    :BUG_SEAL_ORANGE  => "Bug Seal Orange.png",
    :BUG_SEAL_WHITE   => "Bug Seal White.png",   :BUG_SEAL_BLUE    => "Bug Seal Blue.png",
    :GHOST_SEAL_BLACK   => "Ghost Seal Black.png",   :GHOST_SEAL_PURPLE  => "Ghost Seal Purple.png",
    :GHOST_SEAL_GREY    => "Ghost Seal Grey.png",    :GHOST_SEAL_GREEN   => "Ghost Seal Green.png",
    :GHOST_SEAL_YELLOW  => "Ghost Seal Yellow.png",  :GHOST_SEAL_RED     => "Ghost Seal Red.png",
    :GHOST_SEAL_PINK    => "Ghost Seal Pink.png",    :GHOST_SEAL_ORANGE  => "Ghost Seal Orange.png",
    :GHOST_SEAL_WHITE   => "Ghost Seal White.png",   :GHOST_SEAL_BLUE    => "Ghost Seal Blue.png",
    :STEEL_SEAL_BLACK   => "Steel Seal Black.png",   :STEEL_SEAL_PURPLE  => "Steel Seal Purple.png",
    :STEEL_SEAL_GREY    => "Steel Seal Grey.png",    :STEEL_SEAL_GREEN   => "Steel Seal Green.png",
    :STEEL_SEAL_YELLOW  => "Steel Seal Yellow.png",  :STEEL_SEAL_RED     => "Steel Seal Red.png",
    :STEEL_SEAL_PINK    => "Steel Seal Pink.png",    :STEEL_SEAL_ORANGE  => "Steel Seal Orange.png",
    :STEEL_SEAL_WHITE   => "Steel Seal White.png",   :STEEL_SEAL_BLUE    => "Steel Seal Blue.png",
    :WATER_SEAL_BLACK   => "Water Seal Black.png",   :WATER_SEAL_PURPLE  => "Water Seal Purple.png",
    :WATER_SEAL_GREY    => "Water Seal Grey.png",    :WATER_SEAL_GREEN   => "Water Seal Green.png",
    :WATER_SEAL_YELLOW  => "Water Seal Yellow.png",  :WATER_SEAL_RED     => "Water Seal Red.png",
    :WATER_SEAL_PINK    => "Water Seal Pink.png",    :WATER_SEAL_ORANGE  => "Water Seal Orange.png",
    :WATER_SEAL_WHITE   => "Water Seal White.png",   :WATER_SEAL_BLUE    => "Water Seal Blue.png",
    :GRASS_SEAL_BLACK   => "Grass Seal Black.png",   :GRASS_SEAL_PURPLE  => "Grass Seal Purple.png",
    :GRASS_SEAL_GREY    => "Grass Seal Grey.png",    :GRASS_SEAL_GREEN   => "Grass Seal Green.png",
    :GRASS_SEAL_YELLOW  => "Grass Seal Yellow.png",  :GRASS_SEAL_RED     => "Grass Seal Red.png",
    :GRASS_SEAL_PINK    => "Grass Seal Pink.png",    :GRASS_SEAL_ORANGE  => "Grass Seal Orange.png",
    :GRASS_SEAL_WHITE   => "Grass Seal White.png",   :GRASS_SEAL_BLUE    => "Grass Seal Blue.png",
    :PSYCHIC_SEAL_BLACK   => "Psychic Seal Black.png",   :PSYCHIC_SEAL_PURPLE  => "Psychic Seal Purple.png",
    :PSYCHIC_SEAL_GREY    => "Psychic Seal Grey.png",    :PSYCHIC_SEAL_GREEN   => "Psychic Seal Green.png",
    :PSYCHIC_SEAL_YELLOW  => "Psychic Seal Yellow.png",  :PSYCHIC_SEAL_RED     => "Psychic Seal Red.png",
    :PSYCHIC_SEAL_PINK    => "Psychic Seal Pink.png",    :PSYCHIC_SEAL_ORANGE  => "Psychic Seal Orange.png",
    :PSYCHIC_SEAL_WHITE   => "Psychic Seal White.png",   :PSYCHIC_SEAL_BLUE    => "Psychic Seal Blue.png",
    :ICE_SEAL_BLACK   => "Ice Seal Black.png",   :ICE_SEAL_PURPLE  => "Ice Seal Purple.png",
    :ICE_SEAL_GREY    => "Ice Seal Grey.png",    :ICE_SEAL_GREEN   => "Ice Seal Green.png",
    :ICE_SEAL_YELLOW  => "Ice Seal Yellow.png",  :ICE_SEAL_RED     => "Ice Seal Red.png",
    :ICE_SEAL_PINK    => "Ice Seal Pink.png",    :ICE_SEAL_ORANGE  => "Ice Seal Orange.png",
    :ICE_SEAL_WHITE   => "Ice Seal White.png",   :ICE_SEAL_BLUE    => "Ice Seal Blue.png",
    :DRAGON_SEAL_BLACK   => "Dragon Seal Black.png",   :DRAGON_SEAL_PURPLE  => "Dragon Seal Purple.png",
    :DRAGON_SEAL_GREY    => "Dragon Seal Grey.png",    :DRAGON_SEAL_GREEN   => "Dragon Seal Green.png",
    :DRAGON_SEAL_YELLOW  => "Dragon Seal Yellow.png",  :DRAGON_SEAL_RED     => "Dragon Seal Red.png",
    :DRAGON_SEAL_PINK    => "Dragon Seal Pink.png",    :DRAGON_SEAL_ORANGE  => "Dragon Seal Orange.png",
    :DRAGON_SEAL_WHITE   => "Dragon Seal White.png",   :DRAGON_SEAL_BLUE    => "Dragon Seal Blue.png",
    :DARK_SEAL_BLACK   => "Dark Seal Black.png",   :DARK_SEAL_PURPLE  => "Dark Seal Purple.png",
    :DARK_SEAL_GREY    => "Dark Seal Grey.png",    :DARK_SEAL_GREEN   => "Dark Seal Green.png",
    :DARK_SEAL_YELLOW  => "Dark Seal Yellow.png",  :DARK_SEAL_RED     => "Dark Seal Red.png",
    :DARK_SEAL_PINK    => "Dark Seal Pink.png",    :DARK_SEAL_ORANGE  => "Dark Seal Orange.png",
    :DARK_SEAL_WHITE   => "Dark Seal White.png",   :DARK_SEAL_BLUE    => "Dark Seal Blue.png",
    :FAIRY_SEAL_BLACK   => "Fairy Seal Black.png",   :FAIRY_SEAL_PURPLE  => "Fairy Seal Purple.png",
    :FAIRY_SEAL_GREY    => "Fairy Seal Grey.png",    :FAIRY_SEAL_GREEN   => "Fairy Seal Green.png",
    :FAIRY_SEAL_YELLOW  => "Fairy Seal Yellow.png",  :FAIRY_SEAL_RED     => "Fairy Seal Red.png",
    :FAIRY_SEAL_PINK    => "Fairy Seal Pink.png",    :FAIRY_SEAL_ORANGE  => "Fairy Seal Orange.png",
    :FAIRY_SEAL_WHITE   => "Fairy Seal White.png",   :FAIRY_SEAL_BLUE    => "Fairy Seal Blue.png"
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
    # Old Fist_* symbols (renamed to Fighting Seal art)
    :FIST_BLACK   => :FIGHTING_SEAL_BLACK,   :FIST_PURPLE  => :FIGHTING_SEAL_PURPLE,
    :FIST_GREY    => :FIGHTING_SEAL_GREY,    :FIST_GREEN   => :FIGHTING_SEAL_GREEN,
    :FIST_YELLOW  => :FIGHTING_SEAL_YELLOW,  :FIST_RED     => :FIGHTING_SEAL_RED,
    :FIST_PINK    => :FIGHTING_SEAL_PINK,    :FIST_ORANGE  => :FIGHTING_SEAL_ORANGE,
    :FIST_WHITE   => :FIGHTING_SEAL_WHITE,   :FIST_BLUE    => :FIGHTING_SEAL_BLUE
  }

  ("A".."Z").each do |letter|
    LEGACY_SEAL_MAP["#{letter}_SEAL".to_sym] = "#{letter}_SEAL_BLACK".to_sym
  end
  LEGACY_SEAL_MAP[:EXCLAMATION_MARK_SEAL] = :EXCLAMATION_MARK_SEAL_BLACK
  LEGACY_SEAL_MAP[:QUESTION_MARK_SEAL]    = :QUESTION_MARK_SEAL_BLACK
  LEGACY_SEAL_MAP[:SNOW]                  = :ICE_SEAL_WHITE
  LEGACY_SEAL_MAP[:SNOWFLAKE_SEAL_BLACK]  = :ICE_SEAL_BLACK
  LEGACY_SEAL_MAP[:SNOWFLAKE_SEAL_PURPLE] = :ICE_SEAL_PURPLE
  LEGACY_SEAL_MAP[:SNOWFLAKE_SEAL_GREY]   = :ICE_SEAL_GREY
  LEGACY_SEAL_MAP[:SNOWFLAKE_SEAL_GREEN]  = :ICE_SEAL_GREEN
  LEGACY_SEAL_MAP[:SNOWFLAKE_SEAL_YELLOW] = :ICE_SEAL_YELLOW
  LEGACY_SEAL_MAP[:SNOWFLAKE_SEAL_RED]    = :ICE_SEAL_RED
  LEGACY_SEAL_MAP[:SNOWFLAKE_SEAL_PINK]   = :ICE_SEAL_PINK
  LEGACY_SEAL_MAP[:SNOWFLAKE_SEAL_ORANGE] = :ICE_SEAL_ORANGE
  LEGACY_SEAL_MAP[:SNOWFLAKE_SEAL_WHITE]  = :ICE_SEAL_WHITE
  LEGACY_SEAL_MAP[:SNOWFLAKE_SEAL_BLUE]   = :ICE_SEAL_BLUE
  LEGACY_SEAL_MAP[:FIST_SEAL_BLACK]       = :FIGHTING_SEAL_BLACK
  LEGACY_SEAL_MAP[:FIST_SEAL_PURPLE]      = :FIGHTING_SEAL_PURPLE
  LEGACY_SEAL_MAP[:FIST_SEAL_GREY]        = :FIGHTING_SEAL_GREY
  LEGACY_SEAL_MAP[:FIST_SEAL_GREEN]       = :FIGHTING_SEAL_GREEN
  LEGACY_SEAL_MAP[:FIST_SEAL_YELLOW]      = :FIGHTING_SEAL_YELLOW
  LEGACY_SEAL_MAP[:FIST_SEAL_RED]         = :FIGHTING_SEAL_RED
  LEGACY_SEAL_MAP[:FIST_SEAL_PINK]        = :FIGHTING_SEAL_PINK
  LEGACY_SEAL_MAP[:FIST_SEAL_ORANGE]      = :FIGHTING_SEAL_ORANGE
  LEGACY_SEAL_MAP[:FIST_SEAL_WHITE]       = :FIGHTING_SEAL_WHITE
  LEGACY_SEAL_MAP[:FIST_SEAL_BLUE]        = :FIGHTING_SEAL_BLUE

  @bitmaps ||= {}
  @active_fx ||= []
  @replacement_queue ||= []
  @graphics_hook_installed ||= false
  @menu_ensure_calls ||= 0
  @dynamic_seal_defs ||= []
  @dynamic_seal_icon_files ||= {}
  @seal_overlay_vp = nil
  @sprite_bounds_cache ||= {}

  # ── Burst group tracking ────────────────────────────────────────
  # Tracks groups of seal fx entries that belong to the same capsule
  # burst, keyed by an incrementing burst group ID.  Used for multi-
  # pokémon dimming (earlier bursts dim while the newest is active).
  @burst_group_counter ||= 0
  @burst_groups ||= {}

  # ── Sprite bounds detection ──────────────────────────────────────
  # Scans a bitmap's alpha channel to find the non-transparent bounding
  # box.  Returns { :top => y, :bottom => y, :left => x, :right => x,
  # :visible_height => h, :visible_width => w } or nil if fully
  # transparent.  The scan is O(w*h) but each species is only scanned
  # once and the result is cached in @sprite_bounds_cache.

  # Default visible height used when the species sprite cannot be loaded
  # or the bounding-box scan finds nothing.
  DEFAULT_SPRITE_VISIBLE_HEIGHT = 64

  def self.compute_sprite_visible_bounds(bitmap)
    return nil if !bitmap || (bitmap.respond_to?(:disposed?) && bitmap.disposed?)
    w = bitmap.width
    h = bitmap.height
    return nil if w <= 0 || h <= 0
    top    = h
    bottom = 0
    left   = w
    right  = 0
    (0...h).each do |py|
      (0...w).each do |px|
        pixel = bitmap.get_pixel(px, py)
        next if pixel.alpha == 0
        top    = py if py < top
        bottom = py if py > bottom
        left   = px if px < left
        right  = px if px > right
      end
    end
    return nil if top > bottom  # fully transparent
    {
      :top            => top,
      :bottom         => bottom,
      :left           => left,
      :right          => right,
      :visible_height => (bottom - top + 1),
      :visible_width  => (right - left + 1)
    }
  rescue => e
    log("compute_sprite_visible_bounds ERROR: #{e.class}: #{e.message}")
    nil
  end

  # Returns the visible (non-transparent) height of a Pokémon's front
  # sprite in pixels.  Loads the species sprite bitmap independently of
  # the battler sprite timing (which may not be positioned yet) and
  # caches the result per species so the alpha-scan only runs once.
  def self.species_sprite_height(pkmn)
    return DEFAULT_SPRITE_VISIBLE_HEIGHT if !pkmn
    # Determine species key for caching
    species_key = nil
    begin
      if pkmn.respond_to?(:species)
        species_key = pkmn.species
      elsif pkmn.respond_to?(:speciesName)
        species_key = pkmn.speciesName.to_sym
      end
    rescue
    end
    return DEFAULT_SPRITE_VISIBLE_HEIGHT if !species_key
    # Check cache first
    return @sprite_bounds_cache[species_key][:visible_height] if @sprite_bounds_cache[species_key]
    # Try to load the species front sprite via Essentials API
    bmp = nil
    begin
      if defined?(GameData) && defined?(GameData::Species) &&
         GameData::Species.respond_to?(:front_sprite_filename)
        path = GameData::Species.front_sprite_filename(pkmn.species,
                 (pkmn.respond_to?(:form)  ? pkmn.form  : nil),
                 (pkmn.respond_to?(:gender) ? pkmn.gender : nil),
                 (pkmn.respond_to?(:shiny?) ? pkmn.shiny? : false))
        bmp = Bitmap.new(path) if path
      elsif defined?(pbPokemonBitmapFile)
        # Essentials v19 fallback
        path = pbPokemonBitmapFile(pkmn)
        bmp = Bitmap.new(path) if path
      end
    rescue => e
      log("species_sprite_height load ERROR for #{species_key}: #{e.class}: #{e.message}")
    end
    if bmp && (!bmp.respond_to?(:disposed?) || !bmp.disposed?)
      bounds = compute_sprite_visible_bounds(bmp)
      bmp.dispose
      if bounds
        @sprite_bounds_cache[species_key] = bounds
        log("DBG: Cached sprite bounds for #{species_key}: visible_height=#{bounds[:visible_height]}") if $DEBUG
        return bounds[:visible_height]
      end
    end
    # If loading/scanning failed, cache the default so we don't retry
    @sprite_bounds_cache[species_key] = { :visible_height => DEFAULT_SPRITE_VISIBLE_HEIGHT }
    DEFAULT_SPRITE_VISIBLE_HEIGHT
  rescue => e
    log("species_sprite_height ERROR: #{e.class}: #{e.message}")
    DEFAULT_SPRITE_VISIBLE_HEIGHT
  end

  # Returns full cached bounds hash for a species, or nil if not yet
  # computed.  Call species_sprite_height(pkmn) to populate the cache.
  def self.species_sprite_bounds(pkmn)
    species_key = nil
    begin
      species_key = pkmn.species if pkmn && pkmn.respond_to?(:species)
    rescue
    end
    return nil if !species_key
    @sprite_bounds_cache[species_key]
  rescue
    nil
  end

  # Clears the sprite bounds cache.  Called from init_battle so that
  # sprite data is always fresh for each battle session.
  def self.clear_sprite_bounds_cache
    @sprite_bounds_cache = {}
  end

  # ── Seal overlay viewport ──────────────────────────────────────────
  # A dedicated full-screen viewport with a very high z-value so seal
  # animations always render on top of Pokémon sprites, regardless of
  # which viewport the battler sprite lives on (EBDX, Ghost Classic+,
  # vanilla Essentials, etc.).  Created lazily on first use and disposed
  # automatically once all active effects have finished.
  SEAL_OVERLAY_Z = 999999

  def self.seal_overlay_viewport
    if @seal_overlay_vp && !@seal_overlay_vp.disposed?
      return @seal_overlay_vp
    end
    @seal_overlay_vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @seal_overlay_vp.z = SEAL_OVERLAY_Z
    @seal_overlay_vp
  rescue => e
    log("seal_overlay_viewport ERROR: #{e.class}: #{e.message}")
    # Fallback: create and cache a viewport with the correct z so seal
    # rendering is still on top even after an error.
    begin
      @seal_overlay_vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
      @seal_overlay_vp.z = SEAL_OVERLAY_Z
    rescue
      @seal_overlay_vp = nil
    end
    @seal_overlay_vp
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

  def self.single_letter_seal_name?(name)
    !!(name.to_s =~ /\A[A-Za-z] Seal(?: [A-Za-z]+)?\z/)
  end

  def self.punctuation_seal_name?(name)
    !!(name.to_s =~ /\A(?:Exclamation Mark|Question Mark) Seal(?: [A-Za-z]+)?\z/i)
  end

  def self.letter_style_seal_name?(name)
    single_letter_seal_name?(name) || punctuation_seal_name?(name)
  end

  def self.all_seal_defs
    combined = SEAL_DEFS + (@dynamic_seal_defs || [])
    regular = []
    letters = []
    punctuation = []
    combined.each do |s|
      name = s[1].to_s
      if single_letter_seal_name?(name)
        letters << s
      elsif punctuation_seal_name?(name)
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
      !letter_style_seal_name?(name)
    }.sort_by { |s| s[1].downcase }
  end

  # Returns only letter and punctuation (? !) seals.
  def self.letter_seal_defs
    combined = SEAL_DEFS + (@dynamic_seal_defs || [])
    letters = []
    punctuation = []
    combined.each do |s|
      name = s[1].to_s
      if single_letter_seal_name?(name)
        letters << s
      elsif punctuation_seal_name?(name)
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

  # ── Animation group sort helpers ───────────────────────────────
  # Track which animation groups were recently changed so the
  # animations menu can sort by "recently changed".

  def self.anim_group_change_order
    data = ensure_global_data
    return [] if !data
    data[:anim_group_change_order] ||= []
    data[:anim_group_change_order]
  end

  def self.record_anim_group_change(group)
    data = ensure_global_data
    return if !data
    data[:anim_group_change_order] ||= []
    data[:anim_group_change_order].delete(group)
    data[:anim_group_change_order] << group
  end

  # Sort ANIM_GROUPS according to the current anim_sort_mode.
  # :alpha  — alphabetical by display name (default)
  # :recent — most recently changed groups first; unchanged at end
  def self.sorted_anim_groups(groups)
    return groups if !groups || groups.empty?
    case @anim_sort_mode
    when :recent
      order = anim_group_change_order
      groups.sort_by do |g|
        idx = order.index(g)
        idx ? -(idx + 1) : 0
      end
    else # :alpha
      groups.sort_by { |g| intl(ANIM_GROUP_NAMES[g] || g.to_s).downcase }
    end
  end

  def self.anim_sort_mode_label
    case @anim_sort_mode
    when :recent then intl("Sort: Recent")
    else              intl("Sort: A-Z")
    end
  end

  def self.toggle_anim_sort_mode
    @anim_sort_mode = (@anim_sort_mode == :alpha) ? :recent : :alpha
  end

  # Groups an array of seal defs by their category prefix.
  # E.g. "Heart Seal Red" groups under "Heart Seal", "A Seal Red" under "A Seal".
  # Returns an array of [group_name, [seal_defs...]] pairs preserving order.
  def self.group_seal_defs(defs)
    groups = {}
    order = []
    defs.each do |s|
      name = s[1].to_s
      # Extract group name: everything before the last word (color)
      # "Heart Seal Red" => "Heart Seal"
      # "A Seal Pink" => "A Seal"
      # "Exclamation Mark Seal Orange" => "Exclamation Mark Seal"
      parts = name.split(" ")
      if parts.length >= 3
        group = parts[0..-2].join(" ")
      elsif parts.length == 2
        group = parts[0]
      else
        group = name
      end
      if !groups[group]
        groups[group] = []
        order << group
      end
      groups[group] << s
    end
    order.map { |g| [g, groups[g]] }
  end

  # Returns true if the seal symbol corresponds to a letter or punctuation seal.
  def self.letter_seal?(sym)
    name = seal_name(sym).to_s
    letter_style_seal_name?(name)
  end

  # Returns the animation group for a given seal symbol.  Each shape
  # family and Pokémon type family has its own group so users can
  # assign a different animation per seal type per capsule.
  SEAL_PREFIX_TO_GROUP = {
    "HEART_"          => :heart,
    "STAR_"           => :star,
    "SMOKE_"          => :smoke,
    "SONG_"           => :song,
    "FIRE_"           => :fire,
    "SPARKLE_"        => :sparkle_seal,
    "FLOWER_"         => :flower,
    "ELECTRIC_"       => :electric,
    "BUBBLE_"         => :bubble,
    "SKULL_"          => :skull,
    "BAT_"            => :bat,
    "TOMBSTONE_"      => :tombstone,
    "COFFIN_"         => :coffin,
    "NORMAL_SEAL_"    => :normal,
    "FIGHTING_SEAL_"  => :fighting,
    "FLYING_SEAL_"    => :flying,
    "POISON_SEAL_"    => :poison,
    "GROUND_SEAL_"    => :ground,
    "ROCK_SEAL_"      => :rock,
    "BUG_SEAL_"       => :bug,
    "GHOST_SEAL_"     => :ghost_seal,
    "STEEL_SEAL_"     => :steel,
    "WATER_SEAL_"     => :water,
    "GRASS_SEAL_"     => :grass,
    "PSYCHIC_SEAL_"   => :psychic,
    "ICE_SEAL_"       => :ice,
    "DRAGON_SEAL_"    => :dragon,
    "DARK_SEAL_"      => :dark,
    "FAIRY_SEAL_"     => :fairy
  }

  def self.seal_anim_group(sym)
    sym = resolve_seal_sym(sym)
    return :letter if letter_seal?(sym)
    s = sym.to_s
    # Longer prefixes are checked first to avoid false matches (e.g.
    # "FIGHTING_SEAL_" must match before "FIRE_").  Ruby hashes
    # preserve insertion order so we sort by descending prefix length.
    SEAL_PREFIX_TO_GROUP.keys.sort_by { |k| -k.length }.each do |prefix|
      return SEAL_PREFIX_TO_GROUP[prefix] if s.start_with?(prefix)
    end
    :letter  # fallback — dynamic/unknown seals use the letter group
  end

  # Returns the animation type for a seal within a given capsule,
  # honouring per-capsule overrides and falling back to defaults.
  # Supports backward compatibility with old :sparkle and :other group
  # keys from saves created before the per-type group expansion.
  def self.capsule_anim_type(cap, sym)
    group = seal_anim_group(sym)
    settings = (cap && cap[:anim_settings].is_a?(Hash)) ? cap[:anim_settings] : {}
    # 1) Direct match for the current group key
    type = settings[group]
    # 2) Legacy :sparkle key → :sparkle_seal
    if type.nil? && group == :sparkle_seal && settings.key?(:sparkle)
      type = settings[:sparkle]
    end
    # 3) Legacy :other fallback for groups that were previously lumped
    #    under :other (everything except :heart, :sparkle_seal, :letter)
    if type.nil? && group != :heart && group != :sparkle_seal && group != :letter
      type = settings[:other] if settings.key?(:other)
    end
    # 4) Module default
    type = DEFAULT_ANIM_SETTINGS[group] || :static if type.nil?
    ANIM_TYPES.include?(type) ? type : :static
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
    merged_inventory = {}
    (data[:inventory] || {}).each do |sym, qty|
      resolved_sym = resolve_seal_sym(sym)
      current_qty = merged_inventory[resolved_sym]
      merged_inventory[resolved_sym] = current_qty ? [current_qty, qty].max : qty
    end
    default_inventory.each do |sym, qty|
      merged_inventory[sym] = qty unless merged_inventory.key?(sym)
    end
    data[:inventory] = merged_inventory
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
      },
      :anim_settings => (cap[:anim_settings] || {}).dup
    }
  end

  def self.inject_accessors
    if defined?(Pokemon)
      Pokemon.class_eval do
        def ball_capsule_slot; @ball_capsule_slot; end
        def ball_capsule_slot=(val); @ball_capsule_slot = val; end
        def ball_seals; @ball_seals ||= []; @ball_seals; end
        def ball_seals=(arr); @ball_seals = (arr || []).map { |x| x.is_a?(String) ? x.to_sym : x }.compact; end
        # Resolved capsule placements baked onto the Pokémon so they
        # survive Marshal serialization for link battles / trades.
        # Array of { :seal => Symbol, :x => Float, :y => Float } hashes.
        def ball_seal_placements; @ball_seal_placements; end
        def ball_seal_placements=(arr); @ball_seal_placements = arr; end
      end
    end
    if defined?(PokeBattle_Pokemon)
      PokeBattle_Pokemon.class_eval do
        def ball_capsule_slot; @ball_capsule_slot; end
        def ball_capsule_slot=(val); @ball_capsule_slot = val; end
        def ball_seals; @ball_seals ||= []; @ball_seals; end
        def ball_seals=(arr); @ball_seals = (arr || []).map { |x| x.is_a?(String) ? x.to_sym : x }.compact; end
        def ball_seal_placements; @ball_seal_placements; end
        def ball_seal_placements=(arr); @ball_seal_placements = arr; end
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
    # 1) Capsule slot (local save data — always reflects the latest user
    #    assignment, so it must be checked first).
    slot = nil
    slot = pkmn.ball_capsule_slot if pkmn.respond_to?(:ball_capsule_slot)
    if slot && slot >= 1 && slot <= MAX_CAPSULES
      cap = capsule(slot)
      return clone_capsule(cap) if cap
    end
    # 2) Baked placements — set by bake_capsule_to_pokemon before a link
    #    battle or trade so the data survives Marshal serialization to the
    #    remote client.  This is the fallback for when capsule slot data
    #    is unavailable (e.g. on the opponent's client).
    if pkmn.respond_to?(:ball_seal_placements) && pkmn.ball_seal_placements.is_a?(Array) && !pkmn.ball_seal_placements.empty?
      # Re-resolve seal symbols through LEGACY_SEAL_MAP in case the data
      # was baked on an older version with renamed seals, and ensure
      # coords are Floats (Marshal may have preserved Integer 0/1).
      placements = pkmn.ball_seal_placements.map do |p|
        { :seal => resolve_seal_sym(p[:seal]), :x => p[:x].to_f, :y => p[:y].to_f }
      end
      return { :name => "Baked", :placements => placements }
    end
    # 3) Legacy direct seal array
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

  # ── Multiplayer seal data baking ──────────────────────────────────
  # Resolves a Pokémon's capsule (via slot or direct seals) and stores
  # the placements directly on the Pokémon's @ball_seal_placements.
  # This data is a plain Array of { :seal, :x, :y } Hashes that
  # survive Ruby Marshal serialization, ensuring the opponent client
  # receives the full seal layout when Pokémon are exchanged over the
  # wire during link battles or trades.
  #
  # Call bake_seals_for_battle(battle) at battle start (see
  # 003_BallSeals_Battle.rb) to prepare every player-side Pokémon.

  def self.bake_capsule_to_pokemon(pkmn)
    return if !pkmn
    # Clear stale baked data so we always resolve fresh from the current
    # capsule slot rather than potentially re-using outdated placements.
    pkmn.ball_seal_placements = nil if pkmn.respond_to?(:ball_seal_placements=)
    # Resolve from local capsule slot or legacy seals
    slot = pkmn.respond_to?(:ball_capsule_slot) ? pkmn.ball_capsule_slot : nil
    cap = nil
    if slot && slot >= 1 && slot <= MAX_CAPSULES
      cap = capsule(slot)
    end
    if (!cap || !cap[:placements] || cap[:placements].empty?) &&
       pkmn.respond_to?(:ball_seals) && pkmn.ball_seals && !pkmn.ball_seals.empty?
      placements = []
      pkmn.ball_seals[0, MAX_SEALS_PER_CAPSULE].each_with_index do |seal, i|
        ang = (i.to_f / [1, pkmn.ball_seals.length].max) * Math::PI * 2.0
        placements << {
          :seal => resolve_seal_sym(seal),
          :x => 0.5 + Math.cos(ang) * 0.41,
          :y => 0.5 + Math.sin(ang) * 0.32
        }
      end
      cap = { :placements => placements }
    end
    if cap && cap[:placements] && !cap[:placements].empty?
      baked = cap[:placements].map do |p|
        { :seal => resolve_seal_sym(p[:seal]), :x => p[:x].to_f, :y => p[:y].to_f }
      end
      pkmn.ball_seal_placements = baked if pkmn.respond_to?(:ball_seal_placements=)
      log("DBG: Baked #{baked.length} seal placements onto #{pkmn.respond_to?(:name) ? pkmn.name : 'Pokémon'}")
    else
      pkmn.ball_seal_placements = nil if pkmn.respond_to?(:ball_seal_placements=)
    end
  rescue => e
    log("bake_capsule_to_pokemon ERROR: #{e.class}: #{e.message}")
  end

  # Bake seal data onto every Pokémon in the given party array.
  # Typically called with the local player's party before a link
  # battle or trade so the remote client can render seals.
  def self.bake_seals_for_party(party_mons)
    return if !party_mons || !party_mons.is_a?(Array)
    party_mons.each { |pkmn| bake_capsule_to_pokemon(pkmn) }
  end

  def self.enqueue_capsule_for_pokemon(pkmn, idx_battler = nil)
    cap = capsule_for_pokemon(pkmn)
    @replacement_queue << { :cap => cap, :idx_battler => idx_battler, :pkmn => pkmn }
  end

  def self.clear_replacement_queue
    @replacement_queue = []
    @ebdx_ball_index = 0
    @player_sendout_count = 0
    @opponent_sendout_count = 0
  end

  # Track total pokémon being sent out per side so the EBBallBurst
  # hook can detect doubles and apply positional adjustments.
  def self.set_player_sendout_count(n); @player_sendout_count = n; end
  def self.player_sendout_count; @player_sendout_count || 0; end
  def self.set_opponent_sendout_count(n); @opponent_sendout_count = n; end
  def self.opponent_sendout_count; @opponent_sendout_count || 0; end
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
    # Pixel offset applied to all grid X positions so x=0.5 lands on
    # the pokeball's visual centre.
    x_off = (bitmap.width * GRID_X_OFFSET).to_i
    # Try the GUI capsule shape image as an overlay; fall back to
    # the procedurally drawn ellipse.
    capsule_bmp = gui_bitmap(:capsule_shape)
    if capsule_bmp
      dest = Rect.new(16 + x_off, 12, bitmap.width - 32, bitmap.height - 24)
      src  = Rect.new(0, 0, capsule_bmp.width, capsule_bmp.height)
      bitmap.stretch_blt(dest, capsule_bmp, src)
    else
      fill   = Color.new(70, 80, 98)
      border = Color.new(210, 220, 235)
      draw_capsule_shape(bitmap, 16 + x_off, 12, bitmap.width - 32, bitmap.height - 24, fill, border)
    end
    bitmap.fill_rect(20 + x_off, bitmap.height/2 - 1, bitmap.width - 40, 2, Color.new(120,140,160,120))
    # Vertical center line at grid centre (left_pad + range/2)
    vert_x = 16 + x_off + (bitmap.width - 32) / 2
    bitmap.fill_rect(vert_x, 18, 2, bitmap.height - 36, Color.new(120,140,160,100))
    cap = cap || { :placements => [] }
    cap[:placements].each do |pl|
      bx = bitmap_for(pl[:seal])
      next if !bx
      px = 16 + x_off + (pl[:x].to_f * (bitmap.width - 32)).to_i
      py = 12 + (pl[:y].to_f * (bitmap.height - 24)).to_i
      draw_icon(bitmap, bx, px, py, CANVAS_ICON_SIZE)
    end
    if !cursor_x.nil? && !cursor_y.nil?
      px = 16 + x_off + (cursor_x.to_f * (bitmap.width - 32)).to_i
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
  # 80 frames = 4 seconds at 20fps for better timing alignment
  # with Ghost's ball-open animation.
  GHOST_BURST_DELAY = 80

  # Burst delay (in frames) used when Ghost Classic+ is NOT present and
  # EBDX visuals are off (normal/vanilla battle UI).  Delays the seal
  # animation by 4 seconds (80 frames at 20fps) so it syncs with when
  # the pokéball actually opens on screen.
  VANILLA_BURST_DELAY = 80

  # Percentage of screen height to raise (subtract from Y) player-side
  # seal burst animations when Ghost Classic+ UI is detected.  Ghost's
  # battle layout positions sprites differently, causing seal animations
  # to overlap with the Pokémon more than in EBDX.  20% lift keeps the
  # seals visually above the battler sprites.
  GHOST_CLASSIC_Y_RAISE_PCT = 0.20

  # Ghost Classic+ doubles: raise LEFT pokémon's seal burst by 6% of
  # screen height, lower RIGHT pokémon's seal burst by 3%, plus an
  # extra 7% raise for the right pokémon.  Additionally lower the
  # rightmost pokémon's seal animation by 8% when two pokémon are on
  # one side of the field.
  GHOST_DOUBLES_LEFT_RAISE_PCT        = 0.06
  GHOST_DOUBLES_RIGHT_LOWER_PCT       = 0.03
  GHOST_DOUBLES_RIGHT_EXTRA_RAISE_PCT = 0.07
  GHOST_DOUBLES_RIGHT_ANIM_LOWER_PCT  = 0.08

  # Normal battle UI (EBDX off, no Ghost Classic+) doubles: raise LEFT
  # pokémon's seal burst by 6% of screen height, raise RIGHT by 5%.
  VANILLA_DOUBLES_LEFT_RAISE_PCT  = 0.06
  VANILLA_DOUBLES_RIGHT_RAISE_PCT = 0.05

  # EBDX visuals on (no Ghost Classic+) doubles: lower RIGHT pokémon's
  # seal burst by 5% of screen height, shift LEFT pokémon left by 4%
  # of screen width, plus an extra 5% left shift for the left pokémon.
  EBDX_DOUBLES_RIGHT_LOWER_PCT      = 0.05
  EBDX_DOUBLES_X_SHIFT_PCT          = 0.04
  EBDX_DOUBLES_LEFT_EXTRA_SHIFT_PCT = 0.05

  # Triples: raise the 3rd (rightmost) pokémon's seal burst by 14% of
  # screen height.  Applies to all UIs (EBDX, Ghost Classic+, vanilla).
  TRIPLES_THIRD_RAISE_PCT = 0.14
  # EBDX triples: nudge the leftmost player's seal burst right by 3% of
  # screen width to better match the three-Pokémon send-out layout.
  EBDX_TRIPLES_LEFT_X_SHIFT_PCT = 0.03

  # ── Opponent-side burst positioning ─────────────────────────────────
  # For opposing-side (NPC / multiplayer) seal animations, lower bursts
  # by 20% since opponent sprites sit in the upper portion of the screen.
  # Applies to both Ghost Classic+ and EBDX.
  OPPONENT_Y_LOWER_PCT = 0.20

  # Opponent doubles: nudge left opponent's burst left by 3% of screen
  # width, and right opponent's burst right by 3%.
  OPPONENT_DOUBLES_LEFT_X_SHIFT_PCT  = 0.03
  OPPONENT_DOUBLES_RIGHT_X_SHIFT_PCT = 0.03

  # Opponent triples: raise the 3rd (rightmost) opponent's seal burst
  # by 10% of screen height.
  OPPONENT_TRIPLES_THIRD_RAISE_PCT = 0.10

  # Per-pokeball stagger delay (in frames) when multiple pokeballs
  # open at once (e.g. doubles/triples).  The first pokeball's seals
  # play immediately; each subsequent pokeball is delayed by this
  # many additional frames so they animate sequentially.
  # 60 frames = 3 seconds at 20fps — gives each seal animation
  # enough time to play uninterrupted before the next pokeball opens.
  MULTI_BALL_STAGGER = 60

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
      # Map normalised 0..1 placement coords to pixel offsets from burst
      # centre.  Uses 3/4 of the screen dimensions as the spread area so
      # seals fan out proportionally on any resolution.
      spread_w = (Graphics.width  * 0.77).to_i
      spread_h = (Graphics.height * 0.77).to_i
      ox = ((pl[:x].to_f - 0.5) * spread_w).to_i
      oy = ((pl[:y].to_f - 0.5) * spread_h).to_i
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
      # :hold keeps seals at full opacity for ~3.5 seconds (70 frames at 20fps)
      # before the fade-out begins.
      started = burst_delay <= 0
      anim_type = capsule_anim_type(cap, sym)
      @active_fx << { :vp => overlay, :frames => 36, :delay => burst_delay,
                      :hold => 70, :hold_total => 70, :started => started,
                      :particles => particles, :anim_type => anim_type,
                      :seal_index => seal_idx, :total_seals => sorted.length,
                      :base_x => sp.x, :base_y => sp.y,
                      :burst_group => @burst_group_counter }
      # Make visible immediately only when there is no burst delay
      # (animations that manage their own opacity start invisible)
      manages_own_opacity = [:staggered, :explode, :slam, :big_loud].include?(anim_type)
      if started && !manages_own_opacity
        particles.each { |p| p[0].opacity = 255 if p[0] && !p[0].disposed? }
      end
    end
    @burst_group_counter = (@burst_group_counter || 0) + 1
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
    # ── Multi-pokémon dimming ──────────────────────────────────────
    # Find the highest burst_group that is currently in its hold phase
    # (actively animating).  Earlier groups get dimmed.
    newest_active_group = nil
    @active_fx.each do |fx|
      next if !fx[:started] || fx[:started] == false
      next if fx[:delay] && fx[:delay] > 0
      if fx[:hold] && fx[:hold] > 0 && fx[:burst_group]
        if newest_active_group.nil? || fx[:burst_group] > newest_active_group
          newest_active_group = fx[:burst_group]
        end
      end
    end

    # Dim/restore battler sprites for multi-pokémon visibility
    if newest_active_group
      begin
        dim_earlier_battler_sprites(newest_active_group)
      rescue NoMethodError
        # Method defined in 003_BallSeals_Battle.rb; safe to skip if not loaded
      end
    end

    @active_fx.each do |fx|
      # Handle staggered delay — wait before starting animation
      if fx[:delay] && fx[:delay] > 0
        fx[:delay] -= 1
        keep << fx
        next
      end
      # First frame after delay expires: make particles visible
      # (staggered animation keeps seals invisible until their slot)
      if fx[:started] == false
        fx[:started] = true
        anim_type = fx[:anim_type] || :static
        manages_own_opacity = [:staggered, :explode, :slam, :big_loud].include?(anim_type)
        if !manages_own_opacity
          fx[:particles].each do |p|
            sp = p[0]
            sp.opacity = 255 if sp && !sp.disposed?
          end
        end
      end
      # Hold phase — keep seals at full opacity for :hold frames (~3.5 s)
      # before beginning the fade-out, applying per-type animations.
      if fx[:hold] && fx[:hold] > 0
        fx[:hold] -= 1
        apply_hold_animation(fx)
        # Multi-pokémon dimming: if a newer burst group is in hold,
        # dim this group's particles.
        if newest_active_group && fx[:burst_group] &&
           fx[:burst_group] < newest_active_group
          fx[:particles].each do |p|
            sp = p[0]
            next if !sp || sp.disposed?
            sp.opacity = [sp.opacity, MULTI_DIM_OPACITY].min
          end
        end
        keep << fx
        next
      end
      # Reset animation state (zoom, angle, position) before the
      # fade-out begins so the fade is clean regardless of anim type.
      reset_animation_state(fx)
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
    if keep.empty?
      dispose_seal_overlay_viewport
      begin
        restore_battler_sprites
      rescue NoMethodError
        # Method defined in 003_BallSeals_Battle.rb; safe to skip if not loaded
      end
      @burst_group_counter = 0
    end
  rescue => e
    log("update_effects ERROR: #{e.class}: #{e.message}")
  end

  # ── Hold-phase animation dispatch ──────────────────────────────────
  # Applies the chosen animation style to an fx entry during its hold
  # phase.  Called once per frame while :hold > 0.
  def self.apply_hold_animation(fx)
    anim_type = fx[:anim_type] || :static
    return if anim_type == :static

    hold_total = fx[:hold_total] || 70
    elapsed = hold_total - (fx[:hold] || 0)

    fx[:particles].each do |p|
      sp = p[0]
      next if !sp || sp.disposed?

      case anim_type
      when :sparkle
        # Rapid twinkling: modulate zoom and opacity
        twinkle = Math.sin(elapsed * 0.8) * 0.3
        sp.zoom_x = FX_SCALE + twinkle
        sp.zoom_y = FX_SCALE + twinkle
        sp.opacity = 200 + (Math.sin(elapsed * 1.2) * 55).to_i

      when :throb
        # Heartbeat: sharp expand then slow contract, 20-frame cycle
        cycle = elapsed % 20
        if cycle < 4
          scale_mod = (cycle / 4.0) * 0.5
        else
          scale_mod = (1.0 - (cycle - 4) / 16.0) * 0.5
        end
        sp.zoom_x = FX_SCALE + scale_mod
        sp.zoom_y = FX_SCALE + scale_mod

      when :rolling
        # Wave-like vertical oscillation with per-seal phase offsets
        total = [fx[:total_seals] || 1, 1].max
        phase_offset = (fx[:seal_index] || 0) * (Math::PI * 2.0 / total)
        wave = Math.sin(elapsed * 0.25 + phase_offset) * 6
        sp.y = (fx[:base_y] || sp.y) + wave.to_i

      when :wiggle
        # Small angle oscillation in place
        sp.angle = Math.sin(elapsed * 0.5) * 10

      when :staggered
        # Seals fade in one at a time within the hold window
        total = [fx[:total_seals] || 1, 1].max
        idx   = fx[:seal_index] || 0
        stagger_interval = [(hold_total.to_f / total).ceil, 1].max
        seal_start = idx * stagger_interval
        fade_in = 4
        if elapsed < seal_start
          sp.opacity = 0
        elsif elapsed < seal_start + fade_in
          sp.opacity = ((elapsed - seal_start).to_f / fade_in * 255).to_i
        else
          sp.opacity = 255
        end

      when :big_loud
        # iPhone Loud-style: seals appear huge, shrink to large, then
        # pulse/shake vigorously to convey impact.
        if elapsed < 6
          # Rapid scale-down from very large to slightly above normal
          t = elapsed / 6.0
          scale = FX_SCALE * (2.5 - 1.1 * t)
          sp.zoom_x = scale
          sp.zoom_y = scale
          sp.opacity = [255, (t * 255).to_i + 80].min
        else
          # Settled: vigorous shake + pulse at enlarged size
          shake_x = (Math.sin(elapsed * 2.0) * 4).to_i
          shake_y = (Math.cos(elapsed * 2.5) * 3).to_i
          sp.x = (fx[:base_x] || sp.x) + shake_x
          sp.y = (fx[:base_y] || sp.y) + shake_y
          pulse = Math.sin(elapsed * 0.6) * 0.35
          sp.zoom_x = FX_SCALE * 1.35 + pulse
          sp.zoom_y = FX_SCALE * 1.35 + pulse
          sp.opacity = 255
        end

      when :explode
        # iPhone Fireworks-style: seals start tiny at their position,
        # burst outward with spin, then settle at normal size.
        burst_dur = 10
        if elapsed < burst_dur
          # Expand from tiny with rotation
          t = elapsed.to_f / burst_dur
          ease = 1.0 - (1.0 - t) ** 3  # ease-out cubic
          sp.zoom_x = FX_SCALE * (0.15 + 0.85 * ease)
          sp.zoom_y = FX_SCALE * (0.15 + 0.85 * ease)
          sp.angle  = (1.0 - ease) * 540
          sp.opacity = [(ease * 300).to_i, 255].min
        else
          # Settled: slight sparkle pulse after explosion
          shimmer = Math.sin((elapsed - burst_dur) * 0.9) * 0.15
          sp.zoom_x = FX_SCALE + shimmer
          sp.zoom_y = FX_SCALE + shimmer
          sp.angle  = 0
          sp.opacity = 255
        end

      when :slam
        # iPhone Slam-style: seals drop from above with a heavy impact
        # and a brief squash-bounce on landing.
        drop_dur = 8
        bounce_dur = 6
        base_y = fx[:base_y] || sp.y
        if elapsed < drop_dur
          # Drop from above (40px up) with ease-in
          t = elapsed.to_f / drop_dur
          ease_in = t * t  # accelerate downward
          offset_y = ((1.0 - ease_in) * -40).to_i
          sp.y = base_y + offset_y
          sp.zoom_x = FX_SCALE
          sp.zoom_y = FX_SCALE
          sp.opacity = [(t * 320).to_i, 255].min
        elsif elapsed < drop_dur + bounce_dur
          # Squash on impact then spring back
          bt = (elapsed - drop_dur).to_f / bounce_dur
          squash = Math.sin(bt * Math::PI) * 0.35
          sp.zoom_x = FX_SCALE + squash * 0.5   # widen on impact
          sp.zoom_y = FX_SCALE - squash * 0.5   # flatten on impact
          # Small upward bounce
          bounce_y = (Math.sin(bt * Math::PI) * 6).to_i
          sp.y = base_y - bounce_y
          sp.opacity = 255
        else
          # Settled at final position
          sp.zoom_x = FX_SCALE
          sp.zoom_y = FX_SCALE
          sp.y = base_y
          sp.opacity = 255
        end

      when :swirl
        # Seals orbit around their placed position in a circular path.
        # The orbit radius is proportional to the animation spread area
        # so seals stay within the space allocated for effects.
        base_x = fx[:base_x] || sp.x
        base_y = fx[:base_y] || sp.y
        total = [fx[:total_seals] || 1, 1].max
        phase_offset = (fx[:seal_index] || 0) * (Math::PI * 2.0 / total)
        # Orbit radius: 18px keeps the circle tight around the pokémon
        radius = 18
        # Angular speed: ~0.15 rad/frame → full revolution in ~42 frames
        angle_rad = elapsed * 0.15 + phase_offset
        sp.x = base_x + (Math.cos(angle_rad) * radius).to_i
        sp.y = base_y + (Math.sin(angle_rad) * radius).to_i
        sp.zoom_x = FX_SCALE
        sp.zoom_y = FX_SCALE
        sp.opacity = 255

      when :puff
        # Smoke-puff style: seals drift gently side-to-side while
        # fading in and out like a wispy smoke trail / cloud.
        base_x = fx[:base_x] || sp.x
        base_y = fx[:base_y] || sp.y
        total = [fx[:total_seals] || 1, 1].max
        phase_offset = (fx[:seal_index] || 0) * (Math::PI * 2.0 / total)
        # Gentle lateral drift (±8px)
        drift_x = (Math.sin(elapsed * 0.18 + phase_offset) * 8).to_i
        # Slow vertical float (±4px)
        drift_y = (Math.cos(elapsed * 0.12 + phase_offset) * 4).to_i
        sp.x = base_x + drift_x
        sp.y = base_y + drift_y
        # Fade cycle: oscillate opacity between ~80 and 255
        fade = (Math.sin(elapsed * 0.22 + phase_offset) + 1.0) / 2.0
        sp.opacity = (80 + fade * 175).to_i
        # Slight scale pulse to reinforce the puffy feel
        puff_scale = Math.sin(elapsed * 0.16 + phase_offset) * 0.2
        sp.zoom_x = FX_SCALE + puff_scale
        sp.zoom_y = FX_SCALE + puff_scale
      end
    end
  rescue => e
    log("apply_hold_animation ERROR: #{e.class}: #{e.message}")
  end

  # Resets sprite state (zoom, angle, position) to defaults before
  # the fade-out begins.  Ensures a clean transition regardless of
  # which hold-phase animation was active.
  def self.reset_animation_state(fx)
    anim_type = fx[:anim_type] || :static
    return if anim_type == :static

    fx[:particles].each do |p|
      sp = p[0]
      next if !sp || sp.disposed?
      sp.zoom_x = FX_SCALE
      sp.zoom_y = FX_SCALE
      sp.angle  = 0
      sp.x      = fx[:base_x] if fx[:base_x]
      sp.y      = fx[:base_y] if fx[:base_y]
      sp.opacity = 255
    end
  rescue => e
    log("reset_animation_state ERROR: #{e.class}: #{e.message}")
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
    # hold (70) + fade (36) + small buffer (4) = total preview frames
    preview_frames = 70 + 36 + 4
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
        panel_expand = (Graphics.width * 0.03).to_i
        dest = Rect.new(panel_x - 8 - panel_expand, panel_y, Graphics.width - panel_x + panel_expand, win_h)
        src  = Rect.new(0, 0, panel_bmp.width, panel_bmp.height)
        @sprites["bg"].bitmap.stretch_blt(dest, panel_bmp, src)
      end
      @sprites["icon_preview"] = Sprite.new(@viewport)
      @sprites["icon_preview"].x = panel_x + (Graphics.width - panel_x) / 2 - 21 - (Graphics.width * 0.05).to_i
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
