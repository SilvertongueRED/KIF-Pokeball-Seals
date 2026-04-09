# 002_BallSeals_Editor.rb
class BallSealsCapsuleSelectScene
  def choose_slot(prompt = nil)
    commands = BallSealsKIF.capsules.each_with_index.map do |cap, i|
      count = (cap[:placements] || []).length
      "%02d. %s (%d/%d)" % [i + 1, cap[:name], count, BallSealsKIF::MAX_SEALS_PER_CAPSULE]
    end
    idx = BallSealsCommandScene.new(prompt || BallSealsKIF.intl("Choose Capsule"), commands, BallSealsKIF.intl("Pick a slot.")).main
    return nil if idx.nil?
    idx + 1
  end
end

class BallSealsPlaceScene
  def initialize(slot, seal_sym, start_x = nil, start_y = nil)
    @slot = slot
    @seal_sym = seal_sym
    @capsule = BallSealsKIF.clone_capsule(BallSealsKIF.capsule(slot))
    @x = start_x.nil? ? 0.5 : start_x
    @y = start_y.nil? ? 0.5 : start_y
    if start_x.nil? || start_y.nil?
      if !@capsule[:placements].empty?
        @x = @capsule[:placements][-1][:x]
        @y = @capsule[:placements][-1][:y]
      end
    end
  end

  def main
    @viewport = Viewport.new(0,0,Graphics.width,Graphics.height)
    @viewport.z = 99999
    @sprites = {}
    @sprites["bg"] = Sprite.new(@viewport)
    @sprites["bg"].bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @sprites["bg"].bitmap.fill_rect(0,0,Graphics.width,Graphics.height,Color.new(14,18,24))
    # Draw GUI title bar decoration if available
    title_bmp = BallSealsKIF.gui_bitmap(:title_bar)
    if title_bmp
      dest = Rect.new(0, 0, Graphics.width, 38)
      src  = Rect.new(0, 0, title_bmp.width, title_bmp.height)
      @sprites["bg"].bitmap.stretch_blt(dest, title_bmp, src)
    end
    # Draw capsule_bg behind the canvas area
    capsule_bg = BallSealsKIF.gui_bitmap(:capsule_bg)
    if capsule_bg
      dest = Rect.new(8, 64, 256, 192)
      src  = Rect.new(0, 0, capsule_bg.width, capsule_bg.height)
      @sprites["bg"].bitmap.stretch_blt(dest, capsule_bg, src)
    end
    # Draw side_panel behind the seal info/preview area
    panel_bmp = BallSealsKIF.gui_bitmap(:side_panel)
    if panel_bmp
      dest = Rect.new(264, 64, Graphics.width - 280, 192)
      src  = Rect.new(0, 0, panel_bmp.width, panel_bmp.height)
      @sprites["bg"].bitmap.stretch_blt(dest, panel_bmp, src)
    end
    # Draw icon_strip as a thin decorative separator below the title
    strip_bmp = BallSealsKIF.gui_bitmap(:icon_strip)
    if strip_bmp
      dest = Rect.new(0, 60, Graphics.width, 6)
      src  = Rect.new(0, 0, strip_bmp.width, strip_bmp.height)
      @sprites["bg"].bitmap.stretch_blt(dest, strip_bmp, src)
    end
    @sprites["title"] = Window_UnformattedTextPokemon.newWithSize("", 0, 0, Graphics.width, 64, @viewport)
    @sprites["title"].text = BallSealsKIF.intl("Place {1}", BallSealsKIF.seal_name(@seal_sym))[0, 26]
    @sprites["canvas"] = Sprite.new(@viewport)
    @sprites["canvas"].bitmap = Bitmap.new(240, 176)
    @sprites["canvas"].x = 16
    @sprites["canvas"].y = 72
    # Draw seal icon preview on the right side
    @sprites["seal_icon"] = Sprite.new(@viewport)
    seal_bmp = BallSealsKIF.bitmap_for(@seal_sym)
    if seal_bmp
      @sprites["seal_icon"].bitmap = seal_bmp
      @sprites["seal_icon"].x = 296 + (Graphics.width * 0.08).to_i
      @sprites["seal_icon"].y = 90
      @sprites["seal_icon"].zoom_x = 3.0
      @sprites["seal_icon"].zoom_y = 3.0
    end
    # Show seal name label below the icon preview
    @sprites["seal_label"] = Window_UnformattedTextPokemon.newWithSize("", 264, 160, Graphics.width - 264, 56, @viewport)
    @sprites["seal_label"].text = BallSealsKIF.seal_name(@seal_sym)
    @sprites["help"] = Window_UnformattedTextPokemon.newWithSize("", 0, Graphics.height - 88, Graphics.width, 88, @viewport)
    @sprites["help"].text = BallSealsKIF.intl("D-Pad: Move  Confirm: Place  Back: Cancel")
    loop do
      BallSealsKIF.refresh_capsule_canvas(@sprites["canvas"].bitmap, @capsule, @x, @y, @seal_sym)
      Graphics.update
      Input.update
      if Input.repeat?(Input::LEFT)
        @x = [[@x - 0.05, 0.0].max, 1.0].min
      elsif Input.repeat?(Input::RIGHT)
        @x = [[@x + 0.05, 0.0].max, 1.0].min
      elsif Input.repeat?(Input::UP)
        @y = [[@y - 0.05, 0.0].max, 1.0].min
      elsif Input.repeat?(Input::DOWN)
        @y = [[@y + 0.05, 0.0].max, 1.0].min
      elsif Input.trigger?(Input::USE)
        finish = { :seal => @seal_sym, :x => @x, :y => @y }
        dispose
        return finish
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

class BallSealsCapsuleEditorScene
  COMMANDS = [
    "Add Seal",
    "Move Seal",
    "Remove Seal",
    "Rename Capsule",
    "Assign to Pokémon",
    "Clear Capsule",
    "Preview Burst",
    "Back"
  ]

  def initialize(slot)
    @slot = slot
    @capsule = BallSealsKIF.clone_capsule(BallSealsKIF.capsule(slot))
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
    # Draw capsule_bg behind the canvas area
    capsule_bg = BallSealsKIF.gui_bitmap(:capsule_bg)
    if capsule_bg
      dest = Rect.new(8, 64, 256, 192)
      src  = Rect.new(0, 0, capsule_bg.width, capsule_bg.height)
      @sprites["bg"].bitmap.stretch_blt(dest, capsule_bg, src)
    end
    # Draw GUI side panel decoration behind the info area
    panel_bmp = BallSealsKIF.gui_bitmap(:side_panel)
    if panel_bmp
      dest = Rect.new(264, 64, Graphics.width - 280, 240)
      src  = Rect.new(0, 0, panel_bmp.width, panel_bmp.height)
      @sprites["bg"].bitmap.stretch_blt(dest, panel_bmp, src)
    end
    @sprites["title"] = Window_UnformattedTextPokemon.newWithSize("", 0, 0, Graphics.width, 64, @viewport)
    @sprites["canvas"] = Sprite.new(@viewport)
    @sprites["canvas"].bitmap = Bitmap.new(240,176)
    @sprites["canvas"].x = 16
    @sprites["canvas"].y = 72
    @sprites["info"] = Window_UnformattedTextPokemon.newWithSize("", 264, 72, Graphics.width - 280, 232, @viewport)
    @sprites["help"] = Window_UnformattedTextPokemon.newWithSize("", 0, Graphics.height - 72, Graphics.width, 72, @viewport)
    @sprites["help"].text = BallSealsKIF.intl("Use: Actions   Back: Exit")
    refresh

    loop do
      Graphics.update
      Input.update
      if Input.trigger?(Input::USE)
        idx = BallSealsCommandScene.new(BallSealsKIF.intl("Capsule Actions"), COMMANDS.map { |s| BallSealsKIF.intl(s) }, BallSealsKIF.intl("Choose an action.")).main
        break if idx.nil? || idx == COMMANDS.length - 1
        break if handle_command(idx) == :exit
        refresh
      elsif Input.trigger?(Input::BACK)
        break
      end
    end
    dispose
  end

  def handle_command(cmd)
    case cmd
    when 0
      if (@capsule[:placements] || []).length >= BallSealsKIF::MAX_SEALS_PER_CAPSULE
        pbMessage(BallSealsKIF.intl("That capsule already has {1} seals.", BallSealsKIF::MAX_SEALS_PER_CAPSULE))
        return
      end
      add_seal_flow
    when 1 then move_seal_flow
    when 2 then remove_seal_flow
    when 3 then rename_flow
    when 4 then assign_flow
    when 5
      @capsule[:placements] = []
      save_capsule
    when 6
      if !@capsule[:placements] || @capsule[:placements].empty?
        pbMessage(BallSealsKIF.intl("Add at least one seal first."))
      else
        hide_modal_windows
        begin
          BallSealsKIF.preview_capsule(@capsule)
        ensure
          show_modal_windows
        end
      end
    else
      return :exit
    end
    nil
  end

  def dispose
    pbDisposeSpriteHash(@sprites) if @sprites
    @viewport.dispose if @viewport && !@viewport.disposed?
  rescue
  end

  def refresh
    short_name = @capsule[:name].to_s[0, 16]
    @sprites["title"].text = BallSealsKIF.intl("Capsule {1}", @slot)
    BallSealsKIF.refresh_capsule_canvas(@sprites["canvas"].bitmap, @capsule)
    lines = []
    lines << BallSealsKIF.intl("Slot: {1}", @slot)
    lines << BallSealsKIF.intl("Name: {1}", short_name)
    lines << BallSealsKIF.intl("Seals: {1}/{2}", (@capsule[:placements] || []).length, BallSealsKIF::MAX_SEALS_PER_CAPSULE)
    if @capsule[:placements] && !@capsule[:placements].empty?
      lines << ""
      lines << BallSealsKIF.intl("Placed seals:")
      @capsule[:placements][0,5].each_with_index do |pl, i|
        lines << sprintf("%d. %s", i + 1, BallSealsKIF.seal_name(pl[:seal]))
      end
      extra = (@capsule[:placements].length - 5)
      lines << BallSealsKIF.intl("+ {1} more", extra) if extra > 0
    else
      lines << BallSealsKIF.intl("No seals placed.")
      lines << BallSealsKIF.intl("Use Actions to add one.")
    end
    @sprites["info"].text = lines.join("\n")
  end

  def choose_seal
    # Two-step category menu: Shapes vs Letters
    categories = [
      BallSealsKIF.intl("Shapes"),
      BallSealsKIF.intl("Letters"),
      BallSealsKIF.intl("Back")
    ]
    cat_idx = BallSealsCommandScene.new(
      BallSealsKIF.intl("Seal Category"),
      categories,
      BallSealsKIF.intl("Choose a category.")
    ).main
    return nil if cat_idx.nil? || cat_idx == 2
    defs = case cat_idx
           when 0 then BallSealsKIF.shape_seal_defs
           when 1 then BallSealsKIF.letter_seal_defs
           end
    return nil if !defs || defs.empty?
    commands = defs.map { |s| "#{s[1]} x#{BallSealsKIF.inventory[s[0]] || 0}" }
    icons = defs.map { |s| BallSealsKIF.bitmap_for(s[0]) }
    idx = BallSealsCommandScene.new(BallSealsKIF.intl("Choose Seal"), commands, BallSealsKIF.intl("Choose a seal."), 0, nil, icons).main
    return nil if idx.nil?
    defs[idx][0]
  end

  def choose_existing(prompt)
    list = (@capsule[:placements] || [])
    return nil if list.empty?
    commands = list.each_with_index.map { |pl, i| "%d. %s" % [i + 1, BallSealsKIF.seal_name(pl[:seal])] }
    icons = list.map { |pl| BallSealsKIF.bitmap_for(pl[:seal]) }
    idx = BallSealsCommandScene.new(prompt, commands, BallSealsKIF.intl("Choose a placed seal."), 0, nil, icons).main
    return nil if idx.nil?
    idx
  end

  def add_seal_flow
    sym = choose_seal
    return if !sym
    placement = BallSealsPlaceScene.new(@slot, sym).main
    return if !placement
    @capsule[:placements] ||= []
    @capsule[:placements] << placement
    save_capsule
  end

  def move_seal_flow
    idx = choose_existing(BallSealsKIF.intl("Move which seal?"))
    return if idx.nil?
    pl = @capsule[:placements][idx]
    moved = BallSealsPlaceScene.new(@slot, pl[:seal], pl[:x], pl[:y]).main
    return if !moved
    @capsule[:placements][idx] = moved
    save_capsule
  end

  def remove_seal_flow
    idx = choose_existing(BallSealsKIF.intl("Remove which seal?"))
    return if idx.nil?
    @capsule[:placements].delete_at(idx)
    save_capsule
  end

  def hide_modal_windows
    @sprites.each_value do |spr|
      next if !spr
      begin
        spr.visible = false if spr.respond_to?(:visible=)
      rescue
      end
    end
  end

  def show_modal_windows
    @sprites.each_value do |spr|
      next if !spr
      begin
        spr.visible = true if spr.respond_to?(:visible=)
      rescue
      end
    end
    refresh
  end

  def rename_flow
    old = @capsule[:name].to_s
    newname = nil
    hide_modal_windows
    begin
      if defined?(pbEnterText)
        newname = pbEnterText(BallSealsKIF.intl("Capsule name?"), 0, 18, old)
      elsif defined?(pbMessageFreeText)
        newname = pbMessageFreeText(BallSealsKIF.intl("Capsule name?"), old, false, 18, Graphics.width)
      end
    ensure
      show_modal_windows
    end
    return if newname.nil?
    trimmed = newname.to_s.strip
    return if trimmed.empty?
    @capsule[:name] = trimmed[0,18]
    save_capsule
  end

  def assign_flow
    pkmn = BallSealsKIF.choose_party_pokemon(BallSealsKIF.intl("Assign this capsule to which Pokémon?"))
    return if !pkmn
    pkmn.ball_capsule_slot = @slot
    pbMessage(BallSealsKIF.intl("Assigned {1} to {2}.", @capsule[:name], pkmn.name))
  end

  def save_capsule
    BallSealsKIF.set_capsule(@slot, BallSealsKIF.clone_capsule(@capsule))
  end
end
