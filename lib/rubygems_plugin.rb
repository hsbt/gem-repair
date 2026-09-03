require 'rubygems/command_manager'
require 'rubygems/commands/repair_command'
require_relative 'gem_repair/fanout'

Gem::CommandManager.instance.register_command :repair

Gem.post_install do |installer|
  GemRepair::Fanout.run(installer.spec)
end
