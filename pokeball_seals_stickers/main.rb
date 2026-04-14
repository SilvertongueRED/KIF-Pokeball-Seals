# main.rb — Pokeball Seals (Stickers) entry point
# Loaded by the KIF Mod Manager via mod.json "scripts" array.
# Loads all plugin scripts from the mod folder in the correct order.

dir = File.dirname(__FILE__)
%w[
  000_BallSeals_Core
  001_BallSeals_Menu
  002_BallSeals_Editor
  003_BallSeals_Battle
].each { |script| require File.join(dir, script) }
