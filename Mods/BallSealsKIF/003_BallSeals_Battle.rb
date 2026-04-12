# 003_BallSeals_Battle.rb
module BallSealsKIF
  # ── Vanilla/Classic battle burst helper ────────────────────────────
  # Fires seal capsule particle bursts on the battle viewport at the
  # same position the normal ball-open light rays appear.  Works for
  # any scene that is NOT PokeBattle_SceneEBDX (Classic+, vanilla
  # Type 2, etc.).  Called BEFORE the send-out animation so the
  # particles play in parallel with the pokéball opening.
  #
  # When Ghost Classic+ UI is detected the burst is staggered by
  # GHOST_BURST_DELAY frames so the seals appear in sync with Ghost's
  # slightly later ball-open timing.  When Ghost is absent (vanilla
  # EBDX / standard scene) the burst is delayed by VANILLA_BURST_DELAY
  # frames (2 seconds) to sync with the normal ball-open timing.
  def self.trigger_vanilla_burst(scene, send_outs)
    return if !send_outs || send_outs.empty?
    battle  = scene.instance_variable_get(:@battle)  rescue nil
    sprites = scene.instance_variable_get(:@sprites) rescue nil
    vp      = resolve_test_viewport(scene)
    return if !vp
    base_delay = ghost_classic_installed? ? GHOST_BURST_DELAY : VANILLA_BURST_DELAY
    # Count player-side pokémon for doubles detection.
    player_count = 0
    send_outs.each do |pair|
      next if battle && battle.respond_to?(:opposes?) && battle.opposes?(pair[0])
      player_count += 1
    end
    is_doubles = player_count >= 2
    ball_index = 0
    send_outs.each do |pair|
      idxBattler = pair[0]
      pkmn       = pair[1]
      next if battle && battle.respond_to?(:opposes?) && battle.opposes?(idxBattler)
      cap = capsule_for_pokemon(pkmn)
      next if !cap || !cap[:placements] || cap[:placements].empty?
      x, y = player_battler_burst_pos(scene, sprites, idxBattler, pkmn)
      # When Ghost Classic+ UI is detected, raise player-side seal
      # animations by GHOST_CLASSIC_Y_RAISE_PCT of screen height so they
      # sit above the Pokémon sprite instead of overlapping with it.
      if ghost_classic_installed?
        y -= (Graphics.height * GHOST_CLASSIC_Y_RAISE_PCT).to_i
      end
      # Doubles adjustments for player-side seal bursts.
      slot = ((idxBattler || 0) / 2)
      slot = 0 if !slot.is_a?(Integer)
      if is_doubles
        if ghost_classic_installed?
          # Ghost Classic+ doubles: raise left by 6%, lower right by 3%.
          if slot == 0
            y -= (Graphics.height * GHOST_DOUBLES_LEFT_RAISE_PCT).to_i
          elsif slot >= 1
            y += (Graphics.height * GHOST_DOUBLES_RIGHT_LOWER_PCT).to_i
          end
        else
          # Normal battle UI (EBDX off, no Ghost): raise left by 6%,
          # raise right by 5%.
          if slot == 0
            y -= (Graphics.height * VANILLA_DOUBLES_LEFT_RAISE_PCT).to_i
          elsif slot >= 1
            y -= (Graphics.height * VANILLA_DOUBLES_RIGHT_RAISE_PCT).to_i
          end
        end
      end
      # Stagger each successive pokeball's seal burst so they animate
      # sequentially rather than all at once.
      burst_delay = base_delay + (ball_index * MULTI_BALL_STAGGER)
      start_capsule_burst_on_viewport(vp, x, y, cap, burst_delay)
      log("DBG: Triggered vanilla seal burst for battler #{idxBattler} at (#{x},#{y}) delay=#{burst_delay}")
      ball_index += 1
    end
  rescue => e
    log("trigger_vanilla_burst ERROR: #{e.class}: #{e.message}")
  end

  # Determine the best screen position for a player-side battler's
  # ball-open burst.  The hook fires BEFORE pbSendOutBattlers, so the
  # sprite may still be at the RGSS default (0,0) or off-screen.
  # We try several sources and fall back to a safe default.
  #
  # The optional +pkmn+ parameter is used to query the species' visible
  # sprite height (via alpha-channel bounding box scan) so the seal
  # burst is placed above the Pokémon sprite rather than at a hardcoded
  # offset.  The species bitmap is loaded independently of the battler
  # sprite's timing, so it works even before the send-out animation.
  def self.player_battler_burst_pos(scene, sprites, idxBattler, pkmn = nil)
    # Pre-compute the species-specific vertical offset.  This replaces
    # the old hardcoded 64-pixel offset with the actual visible height
    # of the Pokémon's front sprite (determined by alpha-channel scan).
    sprite_h = pkmn ? species_sprite_height(pkmn) : DEFAULT_SPRITE_VISIBLE_HEIGHT
    # Use half the visible height as the upward offset from the battler
    # position so the burst appears centred above the sprite.
    y_offset = [(sprite_h / 2.0).to_i, 16].max

    # 1) Battler sprite — only trust it when already on-screen.
    if sprites
      sprite = sprites["pokemon_#{idxBattler}"] rescue nil
      if sprite && !sprite.disposed? && sprite.x > 0 && sprite.y > 0
        # Account for the sprite's zoom when computing visible height.
        zoom_y = (sprite.respond_to?(:zoom_y) ? sprite.zoom_y : 1.0) rescue 1.0
        zoom_y = 1.0 if zoom_y <= 0
        sy = sprite.y - (y_offset * zoom_y).to_i
        if sy > 0 && sprite.x < Graphics.width && sy < Graphics.height
          return [sprite.x, sy]
        end
      end
    end
    # 2) Scene helper (Essentials v20+ pbBattlerPosition).
    begin
      if scene.respond_to?(:pbBattlerPosition)
        pos = scene.pbBattlerPosition(idxBattler)
        if pos.is_a?(Array) && pos.length >= 2 && pos[0].to_i > 0 && pos[1].to_i > 0
          return [pos[0].to_i, pos[1].to_i - y_offset]
        end
      end
    rescue => e
      BallSealsKIF.log("player_battler_burst_pos pbBattlerPosition ERROR: #{e.class}: #{e.message}")
    end
    # 3) Fallback – approximate centre of the player battler area.
    #    Slot 0 sits at ~1/4 screen width; slot 1 (doubles) shifts right.
    #    Essentials uses even indices for player-side battlers (0, 2, …),
    #    so dividing by 2 gives the slot number within the player's team.
    slot = ((idxBattler || 0) / 2) rescue 0
    dx   = slot * (Graphics.width / 8)
    [Graphics.width / 4 + dx, (Graphics.height * 3) / 4 - y_offset]
  end

  # Resolves the battle scene class across Essentials versions.
  # v19 and earlier: PokeBattle_Scene
  # v20 (compat alias): PokeBattle_Scene = Battle::Scene
  # v21+: Battle::Scene only (PokeBattle_Scene removed)
  def self.resolve_scene_class
    return PokeBattle_Scene if defined?(PokeBattle_Scene)
    return Battle::Scene    if defined?(Battle) && defined?(Battle::Scene)
    nil
  end

  def self.install_sendout_hooks
    return if @sendout_hooks_installed
    patched = []

    # ── EBDX send-out hook ────────────────────────────────────────────
    if defined?(PokeBattle_SceneEBDX) &&
       PokeBattle_SceneEBDX.method_defined?(:playerBattlerSendOut) &&
       !PokeBattle_SceneEBDX.method_defined?(:__bskif_playerBattlerSendOut)
      PokeBattle_SceneEBDX.class_eval do
        alias __bskif_playerBattlerSendOut playerBattlerSendOut
        def playerBattlerSendOut(sendOuts, startBattle = false)
          begin
            BallSealsKIF.clear_replacement_queue
            player_count = 0
            sendOuts.each do |pair|
              idxBattler = pair[0]
              pkmn = pair[1]
              next if @battle && @battle.respond_to?(:opposes?) && @battle.opposes?(idxBattler)
              player_count += 1
              BallSealsKIF.enqueue_replacement_seals(nil)
              BallSealsKIF.enqueue_capsule_for_pokemon(pkmn, idxBattler)
            end
            BallSealsKIF.set_player_sendout_count(player_count)
            BallSealsKIF.log("DBG: Queued capsule replacements for #{sendOuts.length} sendouts (#{player_count} player-side)")
          rescue => e
            BallSealsKIF.log("playerBattlerSendOut queue ERROR: #{e.class}: #{e.message}")
          end
          # If seals-before-pokemon mode is enabled, wait for all seal
          # animations to complete before proceeding with the send-out.
          if BallSealsKIF::SEALS_BEFORE_POKEMON
            begin
              while BallSealsKIF.active_effects_pending?
                Graphics.update
                Input.update rescue nil
              end
            rescue => e
              BallSealsKIF.log("playerBattlerSendOut wait ERROR: #{e.class}: #{e.message}")
            end
          end
          ret = __bskif_playerBattlerSendOut(sendOuts, startBattle)
          begin
            BallSealsKIF.clear_replacement_queue
          rescue
          end
          return ret
        end
      end
      patched << "PokeBattle_SceneEBDX#playerBattlerSendOut"
    end

    # ── Standard / Vanilla / Classic+ scene hooks ─────────────────────
    # Resolves the scene class dynamically so we hook the correct class
    # across Essentials versions (PokeBattle_Scene in v19/v20,
    # Battle::Scene in v21+).  Triggers seal particle bursts at the
    # START of the send-out so they play in sync with the pokéball
    # opening.  Skipped when the scene is a PokeBattle_SceneEBDX
    # instance (EBDX hooks handle it).
    scene_klass = resolve_scene_class
    if scene_klass
      vanilla_hooked = false
      klass_name = scene_klass.name || scene_klass.to_s

      # Batch send-out (preferred): pbSendOutBattlers(sendOuts, startBattle)
      if !vanilla_hooked &&
         scene_klass.method_defined?(:pbSendOutBattlers) &&
         !scene_klass.method_defined?(:__bskif_pbSendOutBattlers)
        scene_klass.class_eval do
          alias __bskif_pbSendOutBattlers pbSendOutBattlers
          def pbSendOutBattlers(sendOuts, startBattle = false)
            # Trigger seal burst BEFORE the send-out animation so that
            # particles play in sync with the pokéball opening, not after.
            if !(defined?(PokeBattle_SceneEBDX) && self.is_a?(PokeBattle_SceneEBDX))
              begin
                BallSealsKIF.trigger_vanilla_burst(self, sendOuts)
              rescue => e
                BallSealsKIF.log("pbSendOutBattlers burst ERROR: #{e.class}: #{e.message}")
              end
              # If seals-before-pokemon mode is enabled, wait for all seal
              # animations to complete before proceeding with the send-out.
              if BallSealsKIF::SEALS_BEFORE_POKEMON
                begin
                  while BallSealsKIF.active_effects_pending?
                    Graphics.update
                    Input.update rescue nil
                  end
                rescue => e
                  BallSealsKIF.log("pbSendOutBattlers wait ERROR: #{e.class}: #{e.message}")
                end
              end
            end
            return __bskif_pbSendOutBattlers(sendOuts, startBattle)
          end
        end
        vanilla_hooked = true
        patched << "#{klass_name}#pbSendOutBattlers"
      end

      # Single send-out fallback: pbSendOut(idxBattler, pkmn)
      if !vanilla_hooked &&
         scene_klass.method_defined?(:pbSendOut) &&
         !scene_klass.method_defined?(:__bskif_pbSendOut)
        scene_klass.class_eval do
          alias __bskif_pbSendOut pbSendOut
          def pbSendOut(idxBattler, pkmn)
            # Trigger seal burst BEFORE the send-out animation.
            if !(defined?(PokeBattle_SceneEBDX) && self.is_a?(PokeBattle_SceneEBDX))
              begin
                BallSealsKIF.trigger_vanilla_burst(self, [[idxBattler, pkmn]])
              rescue => e
                BallSealsKIF.log("pbSendOut burst ERROR: #{e.class}: #{e.message}")
              end
              # If seals-before-pokemon mode is enabled, wait for all seal
              # animations to complete before proceeding with the send-out.
              if BallSealsKIF::SEALS_BEFORE_POKEMON
                begin
                  while BallSealsKIF.active_effects_pending?
                    Graphics.update
                    Input.update rescue nil
                  end
                rescue => e
                  BallSealsKIF.log("pbSendOut wait ERROR: #{e.class}: #{e.message}")
                end
              end
            end
            return __bskif_pbSendOut(idxBattler, pkmn)
          end
        end
        vanilla_hooked = true
        patched << "#{klass_name}#pbSendOut"
      end
    end

    if patched.length > 0
      @sendout_hooks_installed = true
      log("Installed send-out hooks on: #{patched.join(', ')}")
    end
  rescue => e
    log("install_sendout_hooks ERROR: #{e.class}: #{e.message}")
  end

  def self.enqueue_replacement_seals(_dummy)
    # compatibility no-op; queue is capsule-based now
  end

  def self.install_burst_replacement_hook
    return if @burst_hook_installed
    return if !defined?(EBBallBurst)
    methods_public  = EBBallBurst.instance_methods(true).map { |m| m.to_s }
    methods_private = EBBallBurst.private_instance_methods(true).map { |m| m.to_s }
    has_init = methods_public.include?("initialize") || methods_private.include?("initialize")
    has_alias = methods_public.include?("__bskif_initialize") || methods_private.include?("__bskif_initialize")
    return if !has_init
    if has_alias
      @burst_hook_installed = true
      return
    end
    EBBallBurst.class_eval do
      alias __bskif_initialize initialize
      alias __bskif_update update
      alias __bskif_dispose dispose
      def initialize(viewport, x = 0, y = 0, z = 50, factor = 1, balltype = :POKEBALL)
        entry = nil
        cap = nil
        idx_battler = nil
        pkmn = nil
        begin
          if BallSealsKIF.replacement_queue_pending?
            entry = BallSealsKIF.consume_replacement_capsule
            cap = entry[:cap] if entry
            idx_battler = entry[:idx_battler] if entry
            pkmn = entry[:pkmn] if entry
          end
        rescue => e
          BallSealsKIF.log("EBBallBurst initialize consume ERROR: #{e.class}: #{e.message}")
        end
        if cap && cap[:placements] && !cap[:placements].empty?
          @bskif_dummy = true
          @disposed = false
          @viewport = viewport
          # Apply species-specific vertical offset so the seal burst
          # appears above the Pokémon sprite, scaled to its actual
          # visible height instead of a fixed pixel offset.
          burst_y = y
          begin
            sprite_h = pkmn ? BallSealsKIF.species_sprite_height(pkmn) : BallSealsKIF::DEFAULT_SPRITE_VISIBLE_HEIGHT
            y_offset = [(sprite_h / 2.0).to_i, 16].max
            burst_y -= y_offset
          rescue => e
            BallSealsKIF.log("EBBallBurst sprite height ERROR: #{e.class}: #{e.message}")
          end
          # In doubles, adjust seal burst positions to prevent overlap.
          # EBDX visuals on (no Ghost): shift left pokémon left by 4%,
          # lower right by 5%.
          begin
            slot = ((idx_battler || 0) / 2)
            slot = 0 if !slot.is_a?(Integer)
            is_doubles = BallSealsKIF.player_sendout_count >= 2
            if is_doubles
              if slot == 0
                # EBDX doubles: shift left pokémon's burst left by 4%
                # (Ghost Classic not present — it disables EBDX)
                x -= (Graphics.width * BallSealsKIF::EBDX_DOUBLES_X_SHIFT_PCT).to_i
              elsif slot >= 1
                # EBDX doubles: lower right-side seal burst by 5%
                burst_y += (Graphics.height * BallSealsKIF::EBDX_DOUBLES_RIGHT_LOWER_PCT).to_i
              end
            end
          rescue => e
            BallSealsKIF.log("EBBallBurst slot offset ERROR: #{e.class}: #{e.message}")
          end
          # Stagger each successive pokeball's seal burst so they animate
          # sequentially rather than all at once.
          ball_idx = entry[:ball_index] || 0
          stagger_delay = ball_idx * BallSealsKIF::MULTI_BALL_STAGGER
          BallSealsKIF.log("DBG: Replacing vanilla EBBallBurst with capsule burst at (#{x},#{burst_y}) stagger=#{stagger_delay}")
          # Uses the seal icon images for pokeball opening particles
          BallSealsKIF.start_capsule_burst_on_viewport(viewport, x, burst_y, cap, stagger_delay)
          return
        end
        @bskif_dummy = false
        return __bskif_initialize(viewport, x, y, z, factor, balltype)
      end
      def update
        return if @bskif_dummy
        return __bskif_update
      end
      def dispose
        if @bskif_dummy
          @disposed = true
          return
        end
        return __bskif_dispose
      end
      private :initialize
    end
    @burst_hook_installed = true
    log("Installed EBBallBurst replacement hook")
  rescue => e
    log("install_burst_replacement_hook ERROR: #{e.class}: #{e.message}")
  end

  def self.init_battle
    # Reset Ghost detection cache so a fresh check runs every init
    @ghost_classic_detected = nil
    # Clear sprite bounds cache so species data is fresh each battle.
    clear_sprite_bounds_cache
    # Dispose any leftover seal overlay viewport from a previous battle
    # so each battle starts with a clean slate.
    dispose_seal_overlay_viewport
    install_sendout_hooks
    install_burst_replacement_hook
    if ghost_classic_installed?
      log("Ghost Classic+ UI detected — burst delay set to #{GHOST_BURST_DELAY} frames")
    else
      log("Ghost Classic+ UI not detected — using default burst timing")
    end
  end
end

BallSealsKIF.init_battle
