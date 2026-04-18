# 002_BallSeals_Editor.rb
class BallSealsCapsuleSelectScene
  def choose_slot(prompt = nil)
    loop do
      pairs = BallSealsKIF.sorted_capsule_pairs
      sort_label = BallSealsKIF.capsule_sort_mode_label
      commands = [sort_label]
      commands.concat(pairs.map do |slot, cap|
        count = (cap[:placements] || []).length
        "%02d. %s (%d/%d)" % [slot, cap[:name], count, BallSealsKIF::MAX_SEALS_PER_CAPSULE]
      end)
      idx = BallSealsCommandScene.new(prompt || BallSealsKIF.intl("Choose Capsule"), commands, BallSealsKIF.intl("Pick a slot. First option toggles sort.")).main
      return nil if idx.nil?
      if idx == 0
        # Toggle sort mode
        BallSealsKIF.toggle_capsule_sort_mode
        next
      end
      return pairs[idx - 1][0]  # Return the actual slot number
    end
  end
end

class BallSealsPlaceScene
  # Step size reduced 10% from prior 0.0435 (~22% total from original 0.05).
  CURSOR_STEP = 0.03915

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
      dest = Rect.new(264 + (Graphics.width * 0.015).to_i, 64, Graphics.width - 280, 192)
      src  = Rect.new(0, 0, panel_bmp.width, panel_bmp.height)
      @sprites["bg"].bitmap.stretch_blt(dest, panel_bmp, src)
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
      @sprites["seal_icon"].x = 296 + (Graphics.width * 0.055).to_i
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
        @x = [[@x - CURSOR_STEP, 0.0].max, 1.0].min
      elsif Input.repeat?(Input::RIGHT)
        @x = [[@x + CURSOR_STEP, 0.0].max, 1.0].min
      elsif Input.repeat?(Input::UP)
        @y = [[@y - CURSOR_STEP, 0.0].max, 1.0].min
      elsif Input.repeat?(Input::DOWN)
        @y = [[@y + CURSOR_STEP, 0.0].max, 1.0].min
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

# Single-move scene: show capsule canvas with a cursor, let the user
# navigate to a seal and select it with the action button, then move it
# with D-pad and place it with the action button — matching the UX of
# the multi-move scene.
class BallSealsSingleMoveScene
  CANVAS_X = 16
  CANVAS_Y = 72
  CANVAS_W = 240
  CANVAS_H = 176
  # Step size reduced 10% from prior 0.87/32 (~22% total from original 1.0/32).
  # Trade-off: 0.5 (dead centre) may not land exactly on a grid step.
  CURSOR_STEP = 0.783 / 32
  # Max normalised distance from cursor to seal centre for selection
  SELECTION_THRESHOLD = 0.15
  CROSSHAIR_COLOR = Color.new(255, 255, 100)
  HIGHLIGHT_COLOR  = Color.new(100, 200, 255, 100)

  def initialize(slot, capsule)
    @slot = slot
    @capsule = BallSealsKIF.clone_capsule(capsule)
  end

  def main
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @sprites = {}
    @sprites["bg"] = Sprite.new(@viewport)
    @sprites["bg"].bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @sprites["bg"].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(14, 18, 24))
    capsule_bg = BallSealsKIF.gui_bitmap(:capsule_bg)
    if capsule_bg
      dest = Rect.new(8, 64, 256, 192)
      src  = Rect.new(0, 0, capsule_bg.width, capsule_bg.height)
      @sprites["bg"].bitmap.stretch_blt(dest, capsule_bg, src)
    end
    @sprites["title"] = Window_UnformattedTextPokemon.newWithSize("", 0, 0, Graphics.width, 64, @viewport)
    @sprites["title"].text = BallSealsKIF.intl("Move Seal: Select")
    @sprites["canvas"] = Sprite.new(@viewport)
    @sprites["canvas"].bitmap = Bitmap.new(CANVAS_W, CANVAS_H)
    @sprites["canvas"].x = CANVAS_X
    @sprites["canvas"].y = CANVAS_Y
    @sprites["overlay"] = Sprite.new(@viewport)
    @sprites["overlay"].bitmap = Bitmap.new(CANVAS_W, CANVAS_H)
    @sprites["overlay"].x = CANVAS_X
    @sprites["overlay"].y = CANVAS_Y
    @sprites["overlay"].z = @viewport.z + 1
    @sprites["help"] = Window_UnformattedTextPokemon.newWithSize("", 0, Graphics.height - 88, Graphics.width, 88, @viewport)

    # Phase 1: Navigate cursor to a seal and select it
    @sprites["help"].text = BallSealsKIF.intl("D-Pad: Move cursor  Confirm: Select seal  Back: Cancel")
    refresh_canvas
    selected = select_phase
    if selected.nil?
      dispose
      return nil
    end

    # Phase 2: Move the selected seal
    @sprites["title"].text = BallSealsKIF.intl("Move Seal: Place")
    @sprites["help"].text = BallSealsKIF.intl("D-Pad: Move  Confirm: Place  Back: Cancel")
    result = move_phase(selected)
    dispose
    return result
  end

  def select_phase
    placements = @capsule[:placements] || []
    return nil if placements.empty?
    # Start cursor at the first seal's position
    cx = placements[0][:x].to_f
    cy = placements[0][:y].to_f

    loop do
      refresh_canvas
      # Draw cursor crosshair and highlight the nearest seal
      @sprites["overlay"].bitmap.clear
      nearest = nearest_seal(cx, cy)
      if nearest
        draw_seal_highlight(nearest)
      end
      draw_crosshair(cx, cy)

      Graphics.update
      Input.update

      if Input.repeat?(Input::LEFT)
        cx = [[cx - CURSOR_STEP, 0.0].max, 1.0].min
      end
      if Input.repeat?(Input::RIGHT)
        cx = [[cx + CURSOR_STEP, 0.0].max, 1.0].min
      end
      if Input.repeat?(Input::UP)
        cy = [[cy - CURSOR_STEP, 0.0].max, 1.0].min
      end
      if Input.repeat?(Input::DOWN)
        cy = [[cy + CURSOR_STEP, 0.0].max, 1.0].min
      end

      if Input.trigger?(Input::USE)
        idx = nearest_seal(cx, cy)
        return idx if idx
      end

      if Input.trigger?(Input::BACK)
        return nil
      end
    end
  end

  def move_phase(seal_index)
    pl = @capsule[:placements][seal_index]
    off_x = 0.0
    off_y = 0.0

    loop do
      refresh_canvas_with_offset(seal_index, off_x, off_y)

      Graphics.update
      Input.update

      if Input.repeat?(Input::LEFT)
        off_x -= CURSOR_STEP
      end
      if Input.repeat?(Input::RIGHT)
        off_x += CURSOR_STEP
      end
      if Input.repeat?(Input::UP)
        off_y -= CURSOR_STEP
      end
      if Input.repeat?(Input::DOWN)
        off_y += CURSOR_STEP
      end
      if Input.trigger?(Input::USE)
        pl[:x] = [[pl[:x].to_f + off_x, 0.0].max, 1.0].min
        pl[:y] = [[pl[:y].to_f + off_y, 0.0].max, 1.0].min
        return @capsule
      elsif Input.trigger?(Input::BACK)
        return nil
      end
    end
  end

  # Returns the index of the placement nearest to the cursor, or nil.
  def nearest_seal(cx, cy)
    placements = @capsule[:placements] || []
    return nil if placements.empty?
    best_idx = nil
    best_dist = Float::INFINITY
    placements.each_with_index do |pl, i|
      dx = pl[:x].to_f - cx
      dy = pl[:y].to_f - cy
      dist = dx * dx + dy * dy
      if dist < best_dist
        best_dist = dist
        best_idx = i
      end
    end
    # Only select if within a reasonable range (approx half icon size on canvas)
    threshold = SELECTION_THRESHOLD
    best_dist <= threshold * threshold ? best_idx : nil
  end

  def draw_crosshair(cx, cy)
    bmp = @sprites["overlay"].bitmap
    x_off = (CANVAS_W * BallSealsKIF::GRID_X_OFFSET).to_i
    px = (cx * CANVAS_W).to_i + x_off
    py = (cy * CANVAS_H).to_i
    c = CROSSHAIR_COLOR
    hx = [px - 5, 0].max
    hw = [[px + 6, CANVAS_W].min - hx, 0].max
    bmp.fill_rect(hx, py, hw, 1, c)
    vy_start = [py - 5, 0].max
    vh = [[py + 6, CANVAS_H].min - vy_start, 0].max
    bmp.fill_rect(px, vy_start, 1, vh, c)
  end

  def draw_seal_highlight(seal_index)
    pl = @capsule[:placements][seal_index]
    return if !pl
    bmp = @sprites["overlay"].bitmap
    x_off = (CANVAS_W * BallSealsKIF::GRID_X_OFFSET).to_i
    px = 16 + x_off + (pl[:x].to_f * (CANVAS_W - 32)).to_i
    py = 12 + (pl[:y].to_f * (CANVAS_H - 24)).to_i
    size = BallSealsKIF::CANVAS_ICON_SIZE + 4
    bmp.fill_rect(px - size / 2, py - size / 2, size, size, HIGHLIGHT_COLOR)
  end

  def refresh_canvas
    BallSealsKIF.refresh_capsule_canvas(@sprites["canvas"].bitmap, @capsule)
  end

  def refresh_canvas_with_offset(seal_index, off_x, off_y)
    temp_cap = BallSealsKIF.clone_capsule(@capsule)
    pl = temp_cap[:placements][seal_index]
    if pl
      pl[:x] = [[pl[:x].to_f + off_x, 0.0].max, 1.0].min
      pl[:y] = [[pl[:y].to_f + off_y, 0.0].max, 1.0].min
    end
    BallSealsKIF.refresh_capsule_canvas(@sprites["canvas"].bitmap, temp_cap)
    # Highlight the moving seal
    if pl
      bmp = @sprites["canvas"].bitmap
      x_off = (CANVAS_W * BallSealsKIF::GRID_X_OFFSET).to_i
      px = 16 + x_off + (pl[:x].to_f * (CANVAS_W - 32)).to_i
      py = 12 + (pl[:y].to_f * (CANVAS_H - 24)).to_i
      size = BallSealsKIF::CANVAS_ICON_SIZE + 4
      bmp.fill_rect(px - size / 2, py - size / 2, size, size, HIGHLIGHT_COLOR)
    end
  end

  def dispose
    pbDisposeSpriteHash(@sprites) if @sprites
    @viewport.dispose if @viewport && !@viewport.disposed?
  rescue
  end
end

# Multi-move scene: draw capsule canvas, let user drag a selection box
# to select multiple seals, then move them all by an offset.
class BallSealsMultiMoveScene
  CANVAS_X = 16
  CANVAS_Y = 72
  CANVAS_W = 240
  CANVAS_H = 176
  # Step size reduced 10% from prior 0.87/32 (~22% total from original 1.0/32).
  # Trade-off: 0.5 (dead centre) may not land exactly on a grid step.
  CURSOR_STEP = 0.783 / 32

  def initialize(slot, capsule)
    @slot = slot
    @capsule = BallSealsKIF.clone_capsule(capsule)
  end

  def main
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @sprites = {}
    @sprites["bg"] = Sprite.new(@viewport)
    @sprites["bg"].bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @sprites["bg"].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(14, 18, 24))
    capsule_bg = BallSealsKIF.gui_bitmap(:capsule_bg)
    if capsule_bg
      dest = Rect.new(8, 64, 256, 192)
      src  = Rect.new(0, 0, capsule_bg.width, capsule_bg.height)
      @sprites["bg"].bitmap.stretch_blt(dest, capsule_bg, src)
    end
    @sprites["title"] = Window_UnformattedTextPokemon.newWithSize("", 0, 0, Graphics.width, 64, @viewport)
    @sprites["title"].text = BallSealsKIF.intl("Multi-Move: Select Seals")
    @sprites["canvas"] = Sprite.new(@viewport)
    @sprites["canvas"].bitmap = Bitmap.new(CANVAS_W, CANVAS_H)
    @sprites["canvas"].x = CANVAS_X
    @sprites["canvas"].y = CANVAS_Y
    @sprites["overlay"] = Sprite.new(@viewport)
    @sprites["overlay"].bitmap = Bitmap.new(CANVAS_W, CANVAS_H)
    @sprites["overlay"].x = CANVAS_X
    @sprites["overlay"].y = CANVAS_Y
    @sprites["overlay"].z = @viewport.z + 1
    @sprites["help"] = Window_UnformattedTextPokemon.newWithSize("", 0, Graphics.height - 88, Graphics.width, 88, @viewport)

    # Phase 1: Select seals with a drag box
    @sprites["help"].text = BallSealsKIF.intl("Hold Confirm+D-Pad: Draw box  Release: Select  Back: Cancel")
    refresh_canvas
    selected = select_phase
    if !selected || selected.empty?
      dispose
      return nil
    end

    # Phase 2: Move the selected seals together
    @sprites["title"].text = BallSealsKIF.intl("Multi-Move: Drag Seals")
    @sprites["help"].text = BallSealsKIF.intl("D-Pad: Move  Confirm: Place  Back: Cancel")
    result = move_phase(selected)
    dispose
    return result
  end

  def select_phase
    # Cursor for selection box (normalised 0..1 coords on canvas)
    cx = 0.5
    cy = 0.5
    dragging = false
    sel_x1 = 0.0; sel_y1 = 0.0
    sel_x2 = 0.0; sel_y2 = 0.0

    loop do
      refresh_canvas
      # Draw selection box overlay
      @sprites["overlay"].bitmap.clear
      if dragging
        draw_selection_box(sel_x1, sel_y1, cx, cy)
      end
      # Draw cursor crosshair
      x_off = (CANVAS_W * BallSealsKIF::GRID_X_OFFSET).to_i
      px = (cx * CANVAS_W).to_i + x_off
      py = (cy * CANVAS_H).to_i
      c = Color.new(255, 255, 100)
      hx = [px - 5, 0].max
      hw = [[px + 6, CANVAS_W].min - hx, 0].max
      @sprites["overlay"].bitmap.fill_rect(hx, py, hw, 1, c)
      vy_start = [py - 5, 0].max
      vh = [[py + 6, CANVAS_H].min - vy_start, 0].max
      @sprites["overlay"].bitmap.fill_rect(px, vy_start, 1, vh, c)

      Graphics.update
      Input.update

      if Input.repeat?(Input::LEFT)
        cx = [[cx - CURSOR_STEP, 0.0].max, 1.0].min
      end
      if Input.repeat?(Input::RIGHT)
        cx = [[cx + CURSOR_STEP, 0.0].max, 1.0].min
      end
      if Input.repeat?(Input::UP)
        cy = [[cy - CURSOR_STEP, 0.0].max, 1.0].min
      end
      if Input.repeat?(Input::DOWN)
        cy = [[cy + CURSOR_STEP, 0.0].max, 1.0].min
      end

      if Input.press?(Input::USE)
        if !dragging
          # Start drag
          dragging = true
          sel_x1 = cx
          sel_y1 = cy
        end
        # While held, the box extends to current cursor
      else
        if dragging
          # Released — finalize selection
          dragging = false
          sel_x2 = cx
          sel_y2 = cy
          indices = seals_in_box(sel_x1, sel_y1, sel_x2, sel_y2)
          if indices.empty?
            # No seals selected, keep selecting
            next
          end
          return indices
        end
      end

      if Input.trigger?(Input::BACK)
        return nil
      end
    end
  end

  def move_phase(selected_indices)
    # Calculate center of selected seals as the drag anchor
    placements = @capsule[:placements]
    sum_x = 0.0; sum_y = 0.0
    selected_indices.each do |i|
      sum_x += placements[i][:x].to_f
      sum_y += placements[i][:y].to_f
    end
    anchor_x = sum_x / selected_indices.length
    anchor_y = sum_y / selected_indices.length
    # Current offset from anchor
    off_x = 0.0
    off_y = 0.0

    loop do
      # Show preview with moved seals
      refresh_canvas_with_offset(selected_indices, off_x, off_y)

      Graphics.update
      Input.update

      # Use independent if-checks (not elsif) to allow diagonal movement
      if Input.repeat?(Input::LEFT)
        off_x -= CURSOR_STEP
      end
      if Input.repeat?(Input::RIGHT)
        off_x += CURSOR_STEP
      end
      if Input.repeat?(Input::UP)
        off_y -= CURSOR_STEP
      end
      if Input.repeat?(Input::DOWN)
        off_y += CURSOR_STEP
      end
      if Input.trigger?(Input::USE)
        # Apply the offset to selected seals
        selected_indices.each do |i|
          pl = @capsule[:placements][i]
          pl[:x] = [[pl[:x].to_f + off_x, 0.0].max, 1.0].min
          pl[:y] = [[pl[:y].to_f + off_y, 0.0].max, 1.0].min
        end
        return @capsule
      elsif Input.trigger?(Input::BACK)
        return nil
      end
    end
  end

  def seals_in_box(x1, y1, x2, y2)
    min_x = [x1, x2].min
    max_x = [x1, x2].max
    min_y = [y1, y2].min
    max_y = [y1, y2].max
    indices = []
    (@capsule[:placements] || []).each_with_index do |pl, i|
      px = pl[:x].to_f
      py = pl[:y].to_f
      if px >= min_x && px <= max_x && py >= min_y && py <= max_y
        indices << i
      end
    end
    indices
  end

  def draw_selection_box(x1, y1, x2, y2)
    bmp = @sprites["overlay"].bitmap
    x_off = (CANVAS_W * BallSealsKIF::GRID_X_OFFSET).to_i
    px1 = (([x1, x2].min) * CANVAS_W).to_i + x_off
    py1 = (([y1, y2].min) * CANVAS_H).to_i
    px2 = (([x1, x2].max) * CANVAS_W).to_i + x_off
    py2 = (([y1, y2].max) * CANVAS_H).to_i
    w = px2 - px1
    h = py2 - py1
    return if w <= 0 || h <= 0
    box_color = Color.new(100, 200, 255, 80)
    bmp.fill_rect(px1, py1, w, h, box_color)
    border = Color.new(100, 200, 255, 200)
    bmp.fill_rect(px1, py1, w, 1, border)
    bmp.fill_rect(px1, py2, w, 1, border)
    bmp.fill_rect(px1, py1, 1, h, border)
    bmp.fill_rect(px2, py1, 1, h, border)
  end

  def refresh_canvas
    BallSealsKIF.refresh_capsule_canvas(@sprites["canvas"].bitmap, @capsule)
  end

  def refresh_canvas_with_offset(selected_indices, off_x, off_y)
    # Create a temporary capsule with offsets applied for preview
    temp_cap = BallSealsKIF.clone_capsule(@capsule)
    selected_indices.each do |i|
      next if i >= temp_cap[:placements].length
      pl = temp_cap[:placements][i]
      pl[:x] = [[pl[:x].to_f + off_x, 0.0].max, 1.0].min
      pl[:y] = [[pl[:y].to_f + off_y, 0.0].max, 1.0].min
    end
    BallSealsKIF.refresh_capsule_canvas(@sprites["canvas"].bitmap, temp_cap)
    # Highlight selected seals
    bmp = @sprites["canvas"].bitmap
    x_off = (CANVAS_W * BallSealsKIF::GRID_X_OFFSET).to_i
    selected_indices.each do |i|
      next if i >= temp_cap[:placements].length
      pl = temp_cap[:placements][i]
      px = 16 + x_off + (pl[:x].to_f * (CANVAS_W - 32)).to_i
      py = 12 + (pl[:y].to_f * (CANVAS_H - 24)).to_i
      highlight = Color.new(100, 200, 255, 100)
      size = BallSealsKIF::CANVAS_ICON_SIZE + 4
      bmp.fill_rect(px - size / 2, py - size / 2, size, size, highlight)
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
    "Move Seals",
    "Animations",
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
      dest = Rect.new(264 + (Graphics.width * 0.03).to_i, 64, Graphics.width - 280, 240)
      src  = Rect.new(0, 0, panel_bmp.width, panel_bmp.height)
      @sprites["bg"].bitmap.stretch_blt(dest, panel_bmp, src)
    end
    @sprites["title"] = Window_UnformattedTextPokemon.newWithSize("", 0, 0, Graphics.width, 64, @viewport)
    @sprites["canvas"] = Sprite.new(@viewport)
    @sprites["canvas"].bitmap = Bitmap.new(240,176)
    @sprites["canvas"].x = 16
    @sprites["canvas"].y = 72
    @sprites["info"] = Window_UnformattedTextPokemon.newWithSize("", 264 + (Graphics.width * 0.03).to_i, 72 - (Graphics.height * 0.02).to_i, Graphics.width - 280, 232, @viewport)
    @sprites["info"].windowskin = nil
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
      add_seal_flow
    when 1 then move_seal_flow
    when 2 then animations_flow
    when 3 then remove_seal_flow
    when 4 then rename_flow
    when 5 then assign_flow
    when 6
      @capsule[:placements] = []
      save_capsule
    when 7
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
    if !@capsule[:placements] || @capsule[:placements].empty?
      lines << BallSealsKIF.intl("No seals placed.")
      lines << BallSealsKIF.intl("Use Actions to add one.")
    end
    @sprites["info"].text = lines.join("\n")
  end

  def choose_seal
    # Remembers category and seal selection across calls within this editor
    @last_category_idx ||= 0
    @last_seal_idx ||= {}      # category_idx => last command index
    @expanded_groups ||= {}    # category_idx => { group_name => true/false }

    loop do
      # Two-step category menu: Shapes vs Letters
      categories = [
        BallSealsKIF.intl("Shapes"),
        BallSealsKIF.intl("Letters"),
        BallSealsKIF.intl("Back")
      ]
      cat_idx = BallSealsCommandScene.new(
        BallSealsKIF.intl("Seal Category"),
        categories,
        BallSealsKIF.intl("Choose a category."),
        @last_category_idx
      ).main
      return nil if cat_idx.nil? || cat_idx == 2
      @last_category_idx = cat_idx
      # Seal list with sort toggle and collapsible groups — loops so
      # toggling sort or expanding/collapsing re-renders the list.
      result = choose_seal_from_category(cat_idx)
      # nil means user pressed Back in the seal list — return to category
      next if result == :back
      return result
    end
  end

  # Presents a collapsible, grouped seal list for the given category.
  # Returns a seal symbol on selection, :back when the user presses Back
  # (so the caller can return to the category menu), or nil on cancel.
  def choose_seal_from_category(cat_idx)
    @last_seal_idx ||= {}
    @expanded_groups ||= {}
    @expanded_groups[cat_idx] ||= {}

    loop do
      raw_defs = case cat_idx
                 when 0 then BallSealsKIF.shape_seal_defs
                 when 1 then BallSealsKIF.letter_seal_defs
                 end
      return :back if !raw_defs || raw_defs.empty?
      defs = BallSealsKIF.sorted_seal_defs(raw_defs)

      # Build collapsible group structure
      groups = BallSealsKIF.group_seal_defs(defs)
      expanded = @expanded_groups[cat_idx]

      # Build command list: sort toggle, then group headers / items
      commands = [BallSealsKIF.sort_mode_label]
      icons = [nil]
      # Map from command index to action: :sort, [:group, name], [:seal, def]
      actions = [:sort]

      groups.each do |group_name, group_defs|
        is_expanded = expanded[group_name]
        arrow = is_expanded ? "▼" : "▶"
        commands << "#{arrow} #{group_name} (#{group_defs.length})"
        icons << (group_defs.first ? BallSealsKIF.bitmap_for(group_defs.first[0]) : nil)
        actions << [:group, group_name]
        if is_expanded
          group_defs.each do |s|
            commands << "   #{s[1]} x#{BallSealsKIF.inventory[s[0]] || 0}"
            icons << BallSealsKIF.bitmap_for(s[0])
            actions << [:seal, s]
          end
        end
      end

      initial = @last_seal_idx[cat_idx] || 0
      initial = [initial, commands.length - 1].min
      idx = BallSealsCommandScene.new(
        BallSealsKIF.intl("Choose Seal"),
        commands,
        BallSealsKIF.intl("Choose a seal."),
        initial, nil, icons
      ).main

      if idx.nil?
        # User pressed Back — return to category menu
        return :back
      end

      @last_seal_idx[cat_idx] = idx
      action = actions[idx]

      if action == :sort
        BallSealsKIF.toggle_seal_sort_mode
        next
      elsif action.is_a?(Array) && action[0] == :group
        # Toggle expand/collapse
        gname = action[1]
        expanded[gname] = !expanded[gname]
        next
      elsif action.is_a?(Array) && action[0] == :seal
        return action[1][0]
      end
    end
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
    # Loop so the user can add multiple seals without navigating back
    # through the full menu hierarchy each time.
    loop do
      if (@capsule[:placements] || []).length >= BallSealsKIF::MAX_SEALS_PER_CAPSULE
        pbMessage(BallSealsKIF.intl("That capsule already has {1} seals.", BallSealsKIF::MAX_SEALS_PER_CAPSULE))
        return
      end
      sym = choose_seal
      return if !sym
      placement = BallSealsPlaceScene.new(@slot, sym).main
      if placement
        @capsule[:placements] ||= []
        @capsule[:placements] << placement
        BallSealsKIF.record_seal_use(sym)
        save_capsule
        refresh
      end
      # After placing (or cancelling placement), loop back to seal list
    end
  end

  def move_seal_flow
    list = (@capsule[:placements] || [])
    return if list.empty?
    commands = [
      BallSealsKIF.intl("Move One Seal"),
      BallSealsKIF.intl("Move Multiple Seals"),
      BallSealsKIF.intl("Back")
    ]
    choice = BallSealsCommandScene.new(
      BallSealsKIF.intl("Move Seals"),
      commands,
      BallSealsKIF.intl("Choose a move mode.")
    ).main
    return if choice.nil? || choice == 2
    case choice
    when 0
      result = BallSealsSingleMoveScene.new(@slot, @capsule).main
      if result
        @capsule = result
        save_capsule
      end
    when 1
      result = BallSealsMultiMoveScene.new(@slot, @capsule).main
      if result
        @capsule = result
        save_capsule
      end
    end
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
    pkmn.ball_seal_placements = nil if pkmn.respond_to?(:ball_seal_placements=)
    pbMessage(BallSealsKIF.intl("Assigned {1} to {2}.", @capsule[:name], pkmn.name))
  end

  def animations_flow
    loop do
      settings = @capsule[:anim_settings] || {}
      sorted_groups = BallSealsKIF.sorted_anim_groups(BallSealsKIF::ANIM_GROUPS)
      # Sort toggle as the first entry
      commands = [BallSealsKIF.anim_sort_mode_label]
      sorted_groups.each do |group|
        current = settings[group] || BallSealsKIF::DEFAULT_ANIM_SETTINGS[group] || :static
        label = BallSealsKIF.intl(BallSealsKIF::ANIM_GROUP_NAMES[group] || group.to_s)
        type_label = BallSealsKIF.intl(BallSealsKIF::ANIM_TYPE_NAMES[current] || current.to_s)
        commands << "#{label}: #{type_label}"
      end
      commands << BallSealsKIF.intl("Back")

      idx = BallSealsCommandScene.new(
        BallSealsKIF.intl("Animations"),
        commands,
        BallSealsKIF.intl("Choose a seal group to change its animation.")
      ).main

      return if idx.nil? || idx >= commands.length - 1

      # Sort toggle
      if idx == 0
        BallSealsKIF.toggle_anim_sort_mode
        next
      end

      group = sorted_groups[idx - 1]
      type_commands = BallSealsKIF::ANIM_TYPES.map { |t|
        BallSealsKIF.intl(BallSealsKIF::ANIM_TYPE_NAMES[t] || t.to_s)
      }
      current = settings[group] || BallSealsKIF::DEFAULT_ANIM_SETTINGS[group] || :static
      current_idx = BallSealsKIF::ANIM_TYPES.index(current) || 0

      type_idx = BallSealsCommandScene.new(
        BallSealsKIF.intl("Animation Type"),
        type_commands,
        BallSealsKIF.intl("Choose animation for {1}.",
          BallSealsKIF.intl(BallSealsKIF::ANIM_GROUP_NAMES[group] || group.to_s)),
        current_idx
      ).main

      next if type_idx.nil?
      @capsule[:anim_settings] ||= {}
      @capsule[:anim_settings][group] = BallSealsKIF::ANIM_TYPES[type_idx]
      BallSealsKIF.record_anim_group_change(group)
      save_capsule
    end
  end

  def save_capsule
    BallSealsKIF.set_capsule(@slot, BallSealsKIF.clone_capsule(@capsule))
  end
end
