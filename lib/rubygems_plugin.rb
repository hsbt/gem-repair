require 'rubygems/command_manager'
require 'rubygems/commands/repair_command'

Gem::CommandManager.instance.register_command :repair

# Every ruby sharing the GEM_HOME loads this plugin, including ones below the
# required_ruby_version. They still get gem repair, just not the hook.
if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("2.7")
  require_relative 'gem_repair/sweep'
  require_relative 'gem_repair/fanout'

  # Gem::Installer loads this file again when the gem itself is reinstalled.
  unless defined?(GemRepair::HOOKED)
    GemRepair::HOOKED = true
    Gem.post_install do |installer|
      GemRepair::Sweep.clean(installer.spec)
      GemRepair::Fanout.run(installer.spec)
    end
  end
end
