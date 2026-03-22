# 001_BallSeals_Menu.rb
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
        pbMessage(BallSealsKIF.intl("Assigned Capsule {1} to {2}.", slot, pkmn.name))
      when 2
        pkmn = BallSealsKIF.choose_party_pokemon(BallSealsKIF.intl("Remove capsule from which Pokémon?"))
        next if !pkmn
        pkmn.ball_capsule_slot = nil if pkmn.respond_to?(:ball_capsule_slot=)
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

  def self.install_pause_menu_via_menuhandlers
    return false if !defined?(MenuHandlers)
    return false if !MenuHandlers.respond_to?(:add)
    begin
      MenuHandlers.add(:pause_menu, :ball_seals_kif, {
        "name"      => proc { next BallSealsKIF.ball_seals_label },
        "order"     => 69,
        "condition" => proc { next true },
        "effect"    => proc { |menu|
          begin
            pbPlayDecisionSE if defined?(pbPlayDecisionSE)
            menu.pbHideMenu if menu && menu.respond_to?(:pbHideMenu)
          rescue
          end
          BallSealsKIF.open_hub_from_menu
          next false
        }
      })
      log("Pause menu entry installed via MenuHandlers")
      true
    rescue => e
      log("install_pause_menu_via_menuhandlers ERROR: #{e.class}: #{e.message}")
      false
    end
  end

  def self.insert_menu_entry(commands)
    return nil if !commands.is_a?(Array)
    return nil if commands.include?(BallSealsKIF.ball_seals_label)
    cmds = commands.clone
    insert_at = cmds.length
    save_idx = cmds.index(BallSealsKIF.save_label)
    opts_idx = cmds.index(BallSealsKIF.options_label)
    insert_at = save_idx if !save_idx.nil?
    insert_at = opts_idx if save_idx.nil? && !opts_idx.nil?
    cmds.insert(insert_at, BallSealsKIF.ball_seals_label)
    [cmds, insert_at]
  end

  def self.pause_menu_scene_classes
    scene_classes = []
    scene_classes << PokemonPauseMenu_Scene if defined?(PokemonPauseMenu_Scene)
    scene_classes << PokemonPauseMenuScene  if defined?(PokemonPauseMenuScene)
    scene_classes << PauseMenu_Scene        if defined?(PauseMenu_Scene)
    scene_classes << PauseMenuScene         if defined?(PauseMenuScene)
    scene_classes.compact.uniq
  end

  def self.install_pause_menu_hook(force = false)
    pause_menu_scene_classes.each do |klass|
      next if !klass.method_defined?(:pbShowCommands)
      next if klass.method_defined?(:__bskif_pbShowCommands) && !force
      ali = "__bskif_pbShowCommands_late_#{Time.now.to_f.to_s.gsub('.', '_')}".to_sym
      klass.class_eval do
        alias_method ali, :pbShowCommands
        define_method(:pbShowCommands) do |commands, *args|
          begin
            packed = BallSealsKIF.insert_menu_entry(commands)
            if packed
              cmds, insert_at = packed
              ret = send(ali, cmds, *args)
              if ret == insert_at
                BallSealsKIF.open_hub_from_menu
                return -1
              elsif ret && ret > insert_at
                return ret - 1
              else
                return ret
              end
            end
          rescue => e
            BallSealsKIF.log("pbShowCommands late injection ERROR: #{e.class}: #{e.message}")
          end
          send(ali, commands, *args)
        end
      end
      BallSealsKIF.log("Pause menu hook installed on #{klass}#{force ? ' (forced-late)' : ''}")
      return true
    end
    false
  end

  def self.init_menu
    @menu_initial_installed = false
    @menu_late_installed = false
    ok = install_pause_menu_via_menuhandlers
    ok = install_pause_menu_hook(false) if !ok
    @menu_initial_installed = ok
    log("init_menu complete: #{ok ? 'OK' : 'FAILED'}")
  end

  def self.ensure_menu_installed
    @menu_install_attempts ||= 0
    @menu_install_attempts += 1
    return true if @menu_late_installed

    ok = install_pause_menu_hook(true)
    @menu_late_installed = ok

    if ok
      log("ensure_menu_installed forced hook OK (attempt #{@menu_install_attempts})")
    elsif @menu_install_attempts <= 10
      log("ensure_menu_installed pending (attempt #{@menu_install_attempts})")
    end
    ok
  end
end

BallSealsKIF.init_menu
