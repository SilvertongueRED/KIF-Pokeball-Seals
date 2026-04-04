# Mods/BallSealsKIF.rb — KIF mod loader stub
# KIF loads Mods/*.rb files via Dir["./Mods/*.rb"].
# This stub loads the actual plugin scripts from the BallSealsKIF
# subfolder in the correct order.
# Guard prevents re-loading if this file is executed more than once.
unless $__bskif_loader_loaded
  $__bskif_loader_loaded = true
  dir = File.join(File.dirname(__FILE__), "BallSealsKIF")
  if File.directory?(dir)
    Dir.glob(File.join(dir, "*.rb")).sort.each { |f| load f }
  end
end
