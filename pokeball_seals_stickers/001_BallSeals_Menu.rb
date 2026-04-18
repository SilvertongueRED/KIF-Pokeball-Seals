# 001_BallSeals_Menu.rb
# ── Pause-menu integration ─────────────────────────────────────────
# Injects a "Ball Seals" entry into the KIF/Essentials pause menu
# right below "Outfit".  Uses multiple hook strategies to cover
# different KIF engine versions and mod-manager load orders:
#
#   1. MenuHandlers / PauseMenuHandlers  (modern KIF, Essentials v20+)
#   2. Scene class hook via prepend       (standard Essentials v19)
#   3. Screen class hook via prepend      (deferred re-installation)
#   4. Global pbShowCommands hook         (KIF custom pause menu flow)
#
# Strategy 4 is the critical one for KIF: the global pbShowCommands
# function is typically a private method on Object in MKXP's Ruby 2.x,
# so we must check private_method_defined? in addition to method_defined?.
# Strategies 2 & 3 use Module#prepend so they survive later-loading
# scripts that redefine the hooked methods on the same class.

module BallSealsKIF
  def self.ball_seals_label
    @ball_seals_label ||= intl("Ball Seals")
  end

  def self.save_label
    @save_label ||= intl("Save")
  end

  def self.options_label
    @options_label ||= intl("Options")
  end

  def self.outfit_label
    @outfit_label ||= intl("Outfit")
  end

  # Check whether a class/module defines a method (public, protected,
  # OR private).  MKXP Ruby 2.x makes top-level `def` methods private
  # on Object, so plain method_defined? misses them.
  def self.has_any_method?(mod, name)
    mod.method_defined?(name) ||
      mod.private_method_defined?(name)
  rescue
    false
  end
end

class BallSealsHubScene
  def main
    loop do
      cmd = BallSealsCommandScene.new(
        BallSealsKIF.intl("Ball Capsules"),
        [
          BallSealsKIF.intl("Edit Capsules"),
          BallSealsKIF.intl("Assign Capsule"),
          BallSealsKIF.intl("Remove Capsule"),
          BallSealsKIF.intl("Preview Pokémon"),
          BallSealsKIF.intl("Back")
        ],
        BallSealsKIF.intl("Choose a feature.")
      ).main
      break if cmd.nil? || cmd == 4
      case cmd
      when 0
        slot = BallSealsCapsuleSelectScene.new.choose_slot
        next if slot.nil?
        BallSealsCapsuleEditorScene.new(slot).main
      when 1
        pkmn = BallSealsKIF.choose_party_pokemon(BallSealsKIF.intl("Assign which Pokémon?"))
        next if !pkmn
        slot = BallSealsCapsuleSelectScene.new.choose_slot(BallSealsKIF.intl("Assign which capsule?"))
        next if slot.nil?
        pkmn.ball_capsule_slot = slot
        pkmn.ball_seal_placements = nil if pkmn.respond_to?(:ball_seal_placements=)
        pbMessage(BallSealsKIF.intl("Assigned Capsule {1} to {2}.", slot, pkmn.name))
      when 2
        pkmn = BallSealsKIF.choose_party_pokemon(BallSealsKIF.intl("Remove capsule from which Pokémon?"))
        next if !pkmn
        pkmn.ball_capsule_slot = nil if pkmn.respond_to?(:ball_capsule_slot=)
        pkmn.ball_seals = [] if pkmn.respond_to?(:ball_seals=)
        pkmn.ball_seal_placements = nil if pkmn.respond_to?(:ball_seal_placements=)
        pbMessage(BallSealsKIF.intl("Removed Ball Capsule assignment."))
      when 3
        pkmn = BallSealsKIF.choose_party_pokemon(BallSealsKIF.intl("Preview which Pokémon's capsule?"))
        next if !pkmn
        cap = BallSealsKIF.capsule_for_pokemon(pkmn)
        if !cap || !cap[:placements] || cap[:placements].empty?
          pbMessage(BallSealsKIF.intl("That Pokémon has no Ball Capsule effects assigned."))
          next
        end
        BallSealsKIF.test_capsule(cap)
      end
    end
  end
end

module BallSealsKIF
  def self.open_hub_from_menu
    begin
      BallSealsHubScene.new.main
    rescue => e
      log("open_hub_from_menu ERROR: #{e.class}: #{e.message}\n#{(e.backtrace || [])[0,5].join("\n")}")
      pbMessage(intl("Ball Seals error: {1}", e.message.to_s[0, 60])) if defined?(pbMessage)
    end
  end

  # Opens the Ball Seals hub directly (for Overworld Menu integration).
  def self.open_capsule_select
    begin
      BallSealsHubScene.new.main
    rescue => e
      log("open_capsule_select ERROR: #{e.class}: #{e.message}\n#{(e.backtrace || [])[0,5].join("\n")}")
      pbMessage(intl("Ball Seals error: {1}", e.message.to_s[0, 60])) if defined?(pbMessage)
    end
  end

  # ── Case-insensitive label lookup ──────────────────────────────────
  def self.find_label_index(cmds, label)
    target = label.to_s.downcase
    cmds.index { |c| c.to_s.downcase == target }
  end

  # ── Insert "Ball Seals" into a commands array ──────────────────────
  # Returns [modified_commands, insert_index] or nil when no injection
  # is needed (commands isn't an array, or "Ball Seals" is already
  # present).  Prefers placing right after "Outfit"; falls back to
  # right before "Save" or "Options".
  def self.insert_menu_entry(commands)
    return nil if !commands.is_a?(Array) || commands.empty?
    return nil if commands.any? { |c| c.to_s == ball_seals_label.to_s }
    cmds = commands.dup
    insert_at = cmds.length
    # Priority: right after "Outfit"
    outfit_idx = find_label_index(cmds, outfit_label)
    if outfit_idx
      insert_at = outfit_idx + 1
    else
      # Fallback: right before "Save" or "Options"
      save_idx = find_label_index(cmds, save_label)
      opts_idx = find_label_index(cmds, options_label)
      insert_at = save_idx if !save_idx.nil?
      insert_at = opts_idx if save_idx.nil? && !opts_idx.nil?
    end
    cmds.insert(insert_at, ball_seals_label)
    [cmds, insert_at]
  end

  # ── Return-value adjustment ────────────────────────────────────────
  # Adjusts the index returned by the original pbShowCommands to
  # account for the injected "Ball Seals" entry.  Returns -1 (cancel)
  # after opening the hub so the pause menu re-loops.
  def self.handle_menu_return(ret, insert_at)
    if ret == insert_at
      open_hub_from_menu
      return -1
    elsif ret.is_a?(Integer) && ret > insert_at
      return ret - 1
    else
      return ret
    end
  end

  # ── Pause-menu detection ───────────────────────────────────────────
  # Returns true when a commands array looks like it belongs to the
  # KIF / Essentials pause menu.  Used by the global pbShowCommands
  # hook to avoid injecting into unrelated command windows.
  def self.pause_menu_commands?(commands)
    return false if !commands.is_a?(Array) || commands.length < 2
    strs = commands.select { |c| c.is_a?(String) }
    return false if strs.length < 2
    labels = strs.map { |s| s.downcase }
    has_save   = labels.include?(save_label.to_s.downcase)
    has_outfit = labels.include?(outfit_label.to_s.downcase)
    has_opts   = labels.include?(options_label.to_s.downcase)
    quit_labels = ["quit", "exit", "title screen"]
    has_quit   = labels.any? { |l| quit_labels.include?(l) }
    # Require "Save" plus at least one other standard pause menu label
    has_save && (has_outfit || has_opts || has_quit)
  end

  # ── Core hook body (shared) ────────────────────────────────────────
  # Wraps a call to the original pbShowCommands with entry injection
  # and return-value adjustment.  +all_args+ is the full argument list
  # forwarded to the original method; +cmd_arg_idx+ identifies which
  # argument is the commands array.  +&original+ must call the
  # un-hooked implementation.
  def self.wrap_show_commands(all_args, cmd_arg_idx, &original)
    commands = all_args[cmd_arg_idx]
    packed = insert_menu_entry(commands)
    if packed
      cmds, insert_at = packed
      args_mod = all_args.dup
      args_mod[cmd_arg_idx] = cmds
      ret = original.call(*args_mod)
      return handle_menu_return(ret, insert_at)
    end
    nil # signal: nothing to do -- let caller fall through
  end

  # ==================================================================
  # Strategy 1 — MenuHandlers / PauseMenuHandlers (modern engines)
  # ==================================================================
  def self.try_menu_handlers
    [:MenuHandlers, :PauseMenuHandlers].each do |name|
      next unless (Object.const_defined?(name) rescue false)
      handler = Object.const_get(name)
      next unless handler.respond_to?(:add)
      begin
        # order 65: sits between Outfit (~60) and Save (~70) in KIF's
        # default pause menu ordering.
        handler.add(:pause_menu, :ball_seals, {
          "name"      => ball_seals_label,
          "order"     => 65,
          "condition" => proc { true },
          "effect"    => proc { |*| open_hub_from_menu }
        })
        log("Pause menu hook installed via #{name}")
        return true
      rescue => e
        log("#{name} hook failed: #{e.class}: #{e.message}")
      end
    end
    false
  end

  # ==================================================================
  # Strategy 2 — Scene class hook via prepend
  # Uses Module#prepend so the hook survives even when later-loading
  # KIF scripts redefine pbShowCommands on the same class.
  # ==================================================================

  # The prepend module — defined once, prepended to each scene class.
  module SceneMenuHook
    def pbShowCommands(*all_args)
      begin
        result = BallSealsKIF.wrap_show_commands(all_args, 0) { |*a|
          super(*a)
        }
        return result unless result.nil?
      rescue => e
        BallSealsKIF.log("Scene hook ERROR: #{e.class}: #{e.message}")
      end
      super(*all_args)
    end
  end

  def self.install_scene_hooks
    installed = false
    scene_classes = []
    scene_classes << PokemonPauseMenu_Scene if defined?(PokemonPauseMenu_Scene)
    scene_classes << PokemonPauseMenuScene  if defined?(PokemonPauseMenuScene)
    scene_classes << PauseMenu_Scene        if defined?(PauseMenu_Scene)
    scene_classes << PauseMenuScene         if defined?(PauseMenuScene)
    scene_classes.compact.uniq.each do |klass|
      next if !klass.method_defined?(:pbShowCommands)
      # Guard: only prepend once
      next if klass.ancestors.include?(SceneMenuHook)
      klass.send(:prepend, SceneMenuHook)
      BallSealsKIF.log("Pause menu hook installed on #{klass}")
      installed = true
      break
    end
    installed
  end

  # ==================================================================
  # Strategy 3 — Screen class hook via prepend
  # Wraps pbStartPokemonMenu so the global hook (Strategy 4) is
  # retried on every pause-menu open — handles the case where
  # pbShowCommands wasn't yet defined at init time.
  # ==================================================================

  module ScreenMenuHook
    def pbStartPokemonMenu(*args)
      BallSealsKIF.ensure_global_hook
      super(*args)
    end
  end

  def self.install_screen_hooks
    screen_classes = []
    screen_classes << PokemonPauseMenu if defined?(PokemonPauseMenu)
    screen_classes.compact.each do |klass|
      next if !klass.method_defined?(:pbStartPokemonMenu)
      next if klass.ancestors.include?(ScreenMenuHook)
      klass.send(:prepend, ScreenMenuHook)
      BallSealsKIF.log("Screen hook installed on #{klass}")
      return true
    end
    false
  rescue => e
    log("install_screen_hooks ERROR: #{e.class}: #{e.message}")
    false
  end

  # Called from ScreenMenuHook every time the pause menu opens.
  # Retries Strategy 4 if it wasn't installed at init time.
  def self.ensure_global_hook
    install_global_hook unless @global_hook_installed
  rescue => e
    log("ensure_global_hook ERROR: #{e.class}: #{e.message}")
  end

  # ==================================================================
  # Strategy 4 — Global pbShowCommands hook (Object-level)
  # KIF's custom pause menu calls the top-level pbShowCommands
  # function rather than a scene method.  In MKXP's Ruby 2.x, top-
  # level `def` methods are PRIVATE on Object, so we must check
  # private_method_defined? in addition to method_defined?.
  # This hook intercepts those calls but only injects "Ball Seals"
  # when the command list looks like a pause menu (contains "Save" +
  # "Outfit"/"Options"/"Quit").
  # ==================================================================
  def self.install_global_hook
    return false if @global_hook_installed
    return false unless has_any_method?(Object, :pbShowCommands)
    return false if has_any_method?(Object, :__bskif_global_pbShowCommands)
    Object.class_eval do
      alias_method :__bskif_global_pbShowCommands, :pbShowCommands
      define_method(:pbShowCommands) do |*args|
        begin
          # Find the commands array argument (may be args[0] or args[1])
          # depending on whether a helptext string precedes it.
          cmd_arg_idx = nil
          args.each_with_index do |arg, i|
            if arg.is_a?(Array) && BallSealsKIF.pause_menu_commands?(arg)
              cmd_arg_idx = i
              break
            end
          end
          if cmd_arg_idx
            result = BallSealsKIF.wrap_show_commands(args, cmd_arg_idx) { |*a|
              __bskif_global_pbShowCommands(*a)
            }
            return result unless result.nil?
          end
        rescue => e
          BallSealsKIF.log("Global hook ERROR: #{e.class}: #{e.message}")
        end
        __bskif_global_pbShowCommands(*args)
      end
    end
    @global_hook_installed = true
    BallSealsKIF.log("Global pbShowCommands hook installed")
    true
  rescue => e
    log("install_global_hook ERROR: #{e.class}: #{e.message}")
    false
  end

  # ==================================================================
  # Main installer — tries strategies in priority order
  # ==================================================================
  def self.install_pause_menu_hook
    return true if @pause_menu_hook_installed

    # Strategy 1: MenuHandlers (cleanest, no monkeypatching)
    if try_menu_handlers
      @pause_menu_hook_installed = true
      return true
    end

    # Strategy 2: Scene class hook (standard Essentials v19 flow)
    install_scene_hooks

    # Strategy 3: Screen class hook (refreshes scene hooks on menu open)
    install_screen_hooks

    # Strategy 4: Global pbShowCommands hook (catches KIF custom flow)
    install_global_hook

    @pause_menu_hook_installed = true
    true
  end

  def self.init_menu
    ok = install_pause_menu_hook
    install_overworld_menu_entry if defined?(OverworldMenu)
    log("init_menu complete: #{ok ? 'OK' : 'FAILED'}")
  end
end

# ── Global callback for KIF mod manager ────────────────────────────
# KIF's mod manager invokes the method named in mod.json "menu.action"
# at top level.  Define a global helper that delegates to the module.
def open_ball_seals_menu
  BallSealsKIF.open_hub_from_menu
end

BallSealsKIF.init_menu
