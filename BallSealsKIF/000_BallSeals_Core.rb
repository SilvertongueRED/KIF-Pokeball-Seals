# 000_BallSeals_Core.rb
$BallSealsKIFLoaded ||= false
if $BallSealsKIFLoaded
  BallSealsKIF.log("Core load skipped: already loaded") if defined?(BallSealsKIF) && BallSealsKIF.respond_to?(:log)
else
$BallSealsKIFLoaded = true
module BallSealsKIF
  MOD_NAME = "BallSealsKIF"
  MOD_VERSION = "0.1.8-ui-commands-rename-fix"
  LOG_PATH = File.join(Dir.pwd, "Mods", "BallSealsKIF.log") rescue "BallSealsKIF.log"
  MAX_CAPSULES = 12
  MAX_SEALS_PER_CAPSULE = 8
  FX_SCALE = 3.0
  CANVAS_ICON_SIZE = 20

  EXTERNAL_ICON_FILES = {
    :HEART  => "HEART.png",
    :FLOWER => "FLOWER.png",
    :STAR   => "STAR.png",
    :RING   => "RING.png",
    :FIRE   => "FIRE.png",
    :SPARK  => "SPARK.png"
  }

  SEAL_DEFS = [
    [:HEART,     "Heart",      Color.new(255,  90, 140, 220), 6, 10, 0.18, 0.10],
    [:STAR,      "Star",       Color.new(255, 225, 110, 220), 6, 10, 0.16, 0.20],
    [:BUBBLE,    "Bubble",     Color.new(120, 205, 255, 180), 7, 10, -0.03, 0.04],
    [:SPARK,     "Spark",      Color.new(255, 255, 255, 230), 4, 12, 0.10, 0.28],
    [:SMOKE,     "Smoke",      Color.new(135, 135, 135, 170), 8,  8, -0.02, 0.02],
    [:NOTE,      "Note",       Color.new(185, 120, 255, 220), 6,  9, 0.10, 0.08],
    [:FLOWER,    "Flower",     Color.new(255, 150,  65, 220), 6, 10, 0.14, 0.12],
    [:LEAF,      "Leaf",       Color.new(110, 220, 120, 220), 6, 10, 0.16, 0.10],
    [:SNOW,      "Snow",       Color.new(220, 245, 255, 220), 5, 10, 0.04, 0.02],
    [:FIRE,      "Fire",       Color.new(255, 120,  60, 220), 6, 10, 0.22, 0.08],
    [:RING,      "Ring",       Color.new(255, 240, 150, 200), 7,  8, 0.02, 0.06],
    [:DROPLET,   "Droplet",    Color.new( 90, 170, 255, 220), 6, 10, 0.12, 0.05],
    [:CONFETTI,  "Confetti",   Color.new(255, 160, 210, 220), 4, 14, 0.18, 0.24],
    [:BEAM,      "Beam",       Color.new(255, 255, 170, 220), 5,  8, 0.06, 0.00],
    [:CLOUD,     "Cloud",      Color.new(230, 230, 240, 180), 8,  8, -0.01, 0.01],
    [:FLASH,     "Flash",      Color.new(255, 255, 255, 255), 5, 10, 0.08, 0.35]
  ]

  @bitmaps = {}
  @active_fx = []
  @replacement_queue = []
  @graphics_hook_installed = false
  @menu_ensure_calls = 0

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

  def self.seal_defs; SEAL_DEFS; end
  def self.seal_ids; SEAL_DEFS.map { |s| s[0] }; end

  def self.seal_name(sym)
    found = SEAL_DEFS.find { |s| s[0] == sym }
    return found ? found[1] : sym.to_s
  end

  def self.seal_style(sym)
    found = SEAL_DEFS.find { |s| s[0] == sym }
    return found || SEAL_DEFS[0]
  end

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
    capsules[slot - 1] = cap
  end

  def self.clone_capsule(cap)
    {
      :name => (cap[:name] || "CAPSULE"),
      :placements => (cap[:placements] || []).map { |p| { :seal => p[:seal], :x => p[:x], :y => p[:y] } }
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
          :seal => seal,
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

  def self.external_icon_path(sym)
    filename = EXTERNAL_ICON_FILES[sym.to_sym] rescue nil
    return nil if !filename
    path = File.join(Dir.pwd, "Graphics", "BallSeals", "Icons", filename) rescue nil
    return path if path && File.exist?(path)
    nil
  end

  def self.bitmap_for(sym)
    sym = sym.to_sym
    return @bitmaps[sym] if @bitmaps[sym] && !@bitmaps[sym].disposed?
    ext = external_icon_path(sym)
    if ext
      @bitmaps[sym] = Bitmap.new(ext)
      return @bitmaps[sym]
    end
    style = seal_style(sym)
    size = style[3] || 6
    bmp = Bitmap.new(size, size)
    c = style[2] || Color.new(255,255,255,220)
    case sym
    when :HEART
      bmp.fill_rect(1,1,2,2,c); bmp.fill_rect(size-3,1,2,2,c)
      bmp.fill_rect(2,2,size-4,2,c); bmp.fill_rect(3,4,size-6,1,c)
      bmp.fill_rect(size/2,size-2,1,1,c)
    when :STAR, :FLASH
      bmp.fill_rect(size/2,0,1,size,c); bmp.fill_rect(0,size/2,size,1,c)
      bmp.fill_rect(1,1,1,1,c); bmp.fill_rect(size-2,1,1,1,c)
      bmp.fill_rect(1,size-2,1,1,c); bmp.fill_rect(size-2,size-2,1,1,c)
    when :BUBBLE, :RING
      bmp.fill_rect(1,1,size-2,1,c); bmp.fill_rect(1,size-2,size-2,1,c)
      bmp.fill_rect(1,2,1,size-4,c); bmp.fill_rect(size-2,2,1,size-4,c)
    when :SMOKE, :CLOUD
      bmp.fill_rect(1,2,size-2,size-4,c); bmp.fill_rect(2,1,size-4,1,c)
      bmp.fill_rect(2,size-2,size-4,1,c)
    when :NOTE
      bmp.fill_rect(size-2,0,1,size-2,c); bmp.fill_rect(1,size-3,size-2,1,c)
      bmp.fill_rect(0,size-2,2,2,c)
    when :FLOWER
      bmp.fill_rect(size/2,size/2,1,1,c)
      bmp.fill_rect(size/2-1,0,3,1,c); bmp.fill_rect(size/2-1,size-1,3,1,c)
      bmp.fill_rect(0,size/2-1,1,3,c); bmp.fill_rect(size-1,size/2-1,1,3,c)
    else
      bmp.fill_rect(0,0,size,size,c)
    end
    @bitmaps[sym] = bmp
    bmp
  end

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
    fill = Color.new(70, 80, 98)
    border = Color.new(210, 220, 235)
    draw_capsule_shape(bitmap, 16, 12, bitmap.width - 32, bitmap.height - 24, fill, border)
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

  def self.start_capsule_burst_on_viewport(viewport, x, y, cap)
    return if !cap || !cap[:placements] || cap[:placements].empty?
    return if !viewport || (viewport.respond_to?(:disposed?) && viewport.disposed?)
    particles = []
    cap[:placements].each do |pl|
      style = seal_style(pl[:seal])
      sym = style[0]
      bmp = bitmap_for(sym)
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
  def initialize(title, commands, help_text = nil, initial_index = 0, width = nil)
    @title = title
    @commands = commands
    @help_text = help_text
    @initial_index = initial_index || 0
    @width = width || [Graphics.width - 32, 340].max
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
    win_w = [@width, Graphics.width - 32].min
    x = (Graphics.width - win_w) / 2
    y = 68
    @sprites["cmd"] = Window_CommandPokemon.newWithSize(@commands, x, y, win_w, win_h, @viewport)
    @sprites["cmd"].index = [[@initial_index, 0].max, @commands.length - 1].min
    if help_h > 0
      @sprites["help"] = Window_UnformattedTextPokemon.newWithSize(@help_text.to_s, 0, Graphics.height - help_h, Graphics.width, help_h, @viewport)
    end

    loop do
      Graphics.update
      Input.update
      @sprites["cmd"].update
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

  def dispose
    pbDisposeSpriteHash(@sprites) if @sprites
    @viewport.dispose if @viewport && !@viewport.disposed?
  rescue
  end
end

BallSealsKIF.init
end
