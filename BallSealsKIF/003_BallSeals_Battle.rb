# 003_BallSeals_Battle.rb
module BallSealsKIF
  def self.install_sendout_hooks
    return if @sendout_hooks_installed
    patched = []
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
    if patched.length > 0
      @sendout_hooks_installed = true
      log("Installed EBDX send-out hooks on: #{patched.join(', ')}")
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
