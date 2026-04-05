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
      sprite = sprites["pokemon_#{idxBattler}"] rescue nil if sprites
      if sprite && !sprite.disposed?
        x = sprite.x
        # sprite.y is at the feet/ground level; the ball-open light
        # rays appear near the vertical centre of the battler graphic.
        # Move up by half the bitmap height (or a sensible fallback).
        bmp_h = (sprite.bitmap ? sprite.bitmap.height : 0) rescue 0
        y = sprite.y - (bmp_h > 0 ? bmp_h / 2 : 64)
      else
        # Reasonable default when sprite is unavailable – roughly
        # where the player-side battler's centre would be.
        x = Graphics.width / 4
        y = (Graphics.height * 3) / 5
      end
      start_capsule_burst_on_viewport(vp, x, y, cap)
      log("DBG: Triggered vanilla seal burst for battler #{idxBattler} at (#{x},#{y})")
    end
  rescue => e
    log("trigger_vanilla_burst ERROR: #{e.class}: #{e.message}")
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

    # ── Standard / Vanilla / Classic+ PokeBattle_Scene hooks ──────────
    # Triggers seal particle bursts at the START of the send-out so
    # they play in sync with the pokéball opening.  Skipped when the
    # scene is a PokeBattle_SceneEBDX instance (EBDX hooks handle it).
    if defined?(PokeBattle_Scene)
      vanilla_hooked = false

      # Batch send-out (preferred): pbSendOutBattlers(sendOuts, startBattle)
      if !vanilla_hooked &&
         PokeBattle_Scene.method_defined?(:pbSendOutBattlers) &&
         !PokeBattle_Scene.method_defined?(:__bskif_pbSendOutBattlers)
        PokeBattle_Scene.class_eval do
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
        patched << "PokeBattle_Scene#pbSendOutBattlers"
      end

      # Single send-out fallback: pbSendOut(idxBattler, pkmn)
      if !vanilla_hooked &&
         PokeBattle_Scene.method_defined?(:pbSendOut) &&
         !PokeBattle_Scene.method_defined?(:__bskif_pbSendOut)
        PokeBattle_Scene.class_eval do
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
        patched << "PokeBattle_Scene#pbSendOut"
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
          # Uses animation_bitmap_for internally for pokeball opening particles
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
