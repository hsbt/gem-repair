require 'zlib'
require 'rubygems/command'
require 'rubygems/installer'
require 'rubygems/uninstaller'
# see rubygems_plugin.rb
require_relative '../../gem_repair/sweep' if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("2.7")


class Gem::Commands::RepairCommand < Gem::Command
  def initialize
    super 'repair', 'Repairs gems with missing extensions by reinstalling them'

    add_option('-j', '--jobs JOBS', Integer,
               'Number of parallel threads to use (default: 4)') do |value, options|
      options[:jobs] = value
    end

    add_option('--prune',
               'Uninstall gems whose extensions are still missing after repair') do |value, options|
      options[:prune] = true
    end

    add_option('--aggressive-sweep',
               'Also remove the test, spec, features and tmp directories of every gem') do |value, options|
      options[:aggressive_sweep] = true
    end

    add_option('-n', '--dry-run',
               'Show what would be repaired, removed or uninstalled without changing anything') do |value, options|
      options[:dry_run] = true
    end
  end

  def arguments # :nodoc:
    ""
  end

  def description # :nodoc:
    <<-EOF
The repair command finds all installed gems that are missing their compiled
extensions and attempts to reinstall them. This can be useful after upgrading
Ruby or changing system libraries.

It also removes the copies of built extensions that older RubyGems leave in
the lib directory of every gem with extensions, since they shadow the per-ruby
copy for the other rubies sharing the GEM_HOME.

Reinstalling a gem runs the install hooks, so the fan-out to the other rubies
described in the README happens here too.

Use -j to specify the number of parallel threads (default: 4).
Use --prune to uninstall gems that are still missing extensions after repair.
Use --aggressive-sweep to also remove the test, spec, features and tmp
directories of every gem, as gem sweep --aggressive did.
Use -n to only show what would be done.
    EOF
  end

  def usage # :nodoc:
    "#{program_name} [options]"
  end

  def execute
    dry_run = options[:dry_run]
    say "Searching for gems with missing extensions..."

    if defined?(GemRepair::Sweep)
      Gem::Specification.each do |spec|
        GemRepair::Sweep.clean(spec, dry_run: dry_run, aggressive: options[:aggressive_sweep], ui: ui)
      end
    end

    specs = Gem::Specification.select do |spec|
      spec.platform == RUBY_ENGINE && spec.respond_to?(:missing_extensions?) && spec.missing_extensions?
    end

    specs = specs.group_by { |s| [s.name, s.version] }.map do |_, gems|
      non_default_specs = gems.select { |s| !s.default_gem? }
      if non_default_specs.empty?
        gems
      else
        non_default_specs
      end
    end.flatten(1).shuffle

    if specs.empty?
      say "No gems found with missing extensions."
      return
    end

    say "Found #{specs.count} gem(s) to repair: #{specs.map(&:full_name).join(', ')}"

    if dry_run
      specs.each { |spec| say "Would repair #{spec.full_name}" }
      specs.each { |spec| say "Would uninstall #{spec.full_name} unless repaired" } if options[:prune]
      return
    end

    # Get number of threads from -j option, default to 4
    num_threads = options[:jobs] || 4
    # Running Gem::Installer in multiple threads deadlocks on old Rubies
    # (fatal "No live threads left" on Ruby 2.3), so repair sequentially there.
    num_threads = 1 if RUBY_VERSION < "2.6"

    if num_threads > 1
      say "Repairing gems using #{num_threads} parallel threads..."

      queue = Queue.new
      specs.each { |spec| queue << spec }

      threads = num_threads.times.map do
        Thread.new do
          while (spec = (queue.pop(true) rescue nil))
            repair_gem(spec)
          end
        end
      end

      threads.each(&:join)
    else
      say "Repairing gems sequentially..."

      specs.each { |spec| repair_gem(spec) }
    end

    # Reinstalling extracts the gem again, and the install hook only sweeps lib.
    if options[:aggressive_sweep] && defined?(GemRepair::Sweep)
      specs.each { |spec| GemRepair::Sweep.clean(spec, aggressive: true, ui: ui) }
    end

    if options[:prune]
      specs.select(&:missing_extensions?).each { |spec| prune_gem(spec) }
    end

    say "Gem repair process complete."
  end

  private

  def repair_gem(spec)
    say "Repairing #{spec.full_name}..."
    # Ensure spec.base_dir is correct and writable
    # The installer might need specific options, ensure they are correctly set up
    installer_options = {
      wrappers: true,
      force: true, # Reinstall even if it appears installed
      install_dir: spec.base_dir, # Install into the same location
      env_shebang: true,
      build_args: spec.build_args,
      # Add other options as needed, e.g., :user_install => false if installing to system gems
      # ignore_dependencies: true # Usually good for a restore/pristine operation
    }

    # Use spec.cache_file if available and valid, otherwise the installer might re-download
    # Forcing a specific installer might be needed if default behavior isn't right
    installer = if Gem::Installer.respond_to?(:at)
      Gem::Installer.at(spec.cache_file, installer_options)
    else
      # Gem::Installer.at was added in RubyGems 2.5.0 (Ruby 2.3)
      Gem::Installer.new(spec.cache_file, installer_options)
    end
    installer.install
    say "Successfully repaired #{spec.full_name} to #{spec.base_dir}"
  rescue Gem::Ext::BuildError, Gem::Package::FormatError, Gem::InstallError, Zlib::BufError, NameError => e
    alert_error "Failed to repair #{spec.full_name}: #{e.message}\n  Backtrace: #{e.backtrace.join("\n             ")}"
  rescue => e
    alert_error "An unexpected error occurred while repairing #{spec.full_name}: #{e.message}\n  Backtrace: #{e.backtrace.join("\n             ")}"
  end

  def prune_gem(spec)
    # force skips the dependent-gem prompt, which RubyGems answers no to off a tty.
    Gem::Uninstaller.new(spec.name, version: spec.version, install_dir: spec.base_dir, executables: true, force: true).uninstall_gem(spec)
  rescue Gem::Exception => e
    alert_error "Failed to uninstall #{spec.full_name}: #{e.message}"
  end
end
