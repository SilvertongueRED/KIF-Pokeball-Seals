# 003_BallSeals_Battle.rb
module BallSealsKIF
  # ── Vanilla/Classic battle burst helper ────────────────────────────
  # Fires seal capsule particle bursts on the battle viewport at the
  # same position the normal ball-open light rays appear.  Works for
  # any scene that is NOT PokeBattle_SceneEBDX (Classic+, vanilla
  # Type 2, etc.).  Called BEFORE the send-out animation so the
  # particles play in parallel with the pokéball opening.
  def self.trigger_vanilla_burst(scene, send_outs)
    return if !send_outs || send_outs.empty?
    battle  = scene.instance_variable_get(:@battle)  rescue nil
    sprites = scene.instance_variable_get(:@sprites) rescue nil
    vp      = resolve_test_viewport(scene)
    return if !vp
    send_outs.each do |pair|
      idxBattler = pair[0]
      pkmn       = pair[1]
      next if battle && battle.respond_to?(:opposes?) && battle.opposes?(idxBattler)
      cap = capsule_for_pokemon(pkmn)
      next if !cap || !cap[:placements] || cap[:placements].empty?
      x, y = player_battler_burst_pos(scene, sprites, idxBattler)
      start_capsule_burst_on_viewport(vp, x, y, cap)
      log("DBG: Triggered vanilla seal burst for battler #{idxBattler} at (#{x},#{y})")
    end
  rescue => e
    log("trigger_vanilla_burst ERROR: #{e.class}: #{e.message}")
  end

  # Determine the best screen position for a player-side battler's
  # ball-open burst.  The hook fires BEFORE pbSendOutBattlers, so the
  # sprite may still be at the RGSS default (0,0) or off-screen.
  # We try several sources and fall back to a safe default.
  def self.player_battler_burst_pos(scene, sprites, idxBattler)
    # 1) Battler sprite — only trust it when already on-screen.
    if sprites
      sprite = sprites["pokemon_#{idxBattler}"] rescue nil
      if sprite && !sprite.disposed? && sprite.x > 0 && sprite.y > 0
        bmp_h = (sprite.bitmap ? sprite.bitmap.height : 0) rescue 0
        sy = sprite.y - (bmp_h > 0 ? bmp_h / 2 : 64)
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
          return [pos[0].to_i, pos[1].to_i - 64]
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
    [Graphics.width / 4 + dx, (Graphics.height * 3) / 4]
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
            sendOuts.each do |pair|
              idxBattler = pair[0]
              pkmn = pair[1]
              next if @battle && @battle.respond_to?(:opposes?) && @battle.opposes?(idxBattler)
              BallSealsKIF.enqueue_replacement_seals(nil)
              BallSealsKIF.enqueue_capsule_for_pokemon(pkmn)
            end
            BallSealsKIF.log("DBG: Queued capsule replacements for #{sendOuts.length} sendouts")
          rescue => e
            BallSealsKIF.log("playerBattlerSendOut queue ERROR: #{e.class}: #{e.message}")
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
        cap = nil
        begin
          if BallSealsKIF.replacement_queue_pending?
            cap = BallSealsKIF.consume_replacement_capsule
          end
        rescue => e
          BallSealsKIF.log("EBBallBurst initialize consume ERROR: #{e.class}: #{e.message}")
        end
        if cap && cap[:placements] && !cap[:placements].empty?
          @bskif_dummy = true
          @disposed = false
          @viewport = viewport
          BallSealsKIF.log("DBG: Replacing vanilla EBBallBurst with capsule burst at (#{x},#{y})")
          # Uses the seal icon images for pokeball opening particles
          BallSealsKIF.start_capsule_burst_on_viewport(viewport, x, y, cap)
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
    install_sendout_hooks
    install_burst_replacement_hook
  end
end

BallSealsKIF.init_battle
