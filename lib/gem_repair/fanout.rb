# frozen_string_literal: true

require "rbconfig"

module GemRepair
  # Builds the extensions of a freshly installed gem for the other rubies that
  # share its GEM_HOME, so switching rubies does not leave the gem ignored
  # with "extensions are not built".
  #
  # Rubies are looked up under the install roots of mise (MISE_DATA_DIR,
  # default XDG_DATA_HOME/mise) and rbenv (RBENV_ROOT, default ~/.rbenv).
  # GEM_REPAIR_RUBIES narrows them to a comma-separated list of version names.
  # An empty value disables the fan-out.
  module Fanout
    SKIP = /\A(jruby|truffleruby|mruby|rbx)/

    # Runs inside each target ruby. Exit 2 means there was nothing to do.
    # spec_file pins the lookup to the shared copy the parent just installed.
    # install_extension_in_lib is forced off for the reason in GemRepair::Sweep.
    BUILD = <<~'RUBY'
      $VERBOSE = nil
      exit 2 unless defined?(Gem::Specification) && Gem::Specification.method_defined?(:missing_extensions?)
      name, version, spec_file = ARGV
      spec = Gem::Specification.find_all_by_name(name, version).find { |s| s.spec_file == spec_file }
      exit 2 if spec.nil? || spec.default_gem? || !spec.missing_extensions?
      exit 2 unless spec.required_ruby_version.satisfied_by?(Gem.ruby_version)
      def Gem.install_extension_in_lib; false; end
      begin
        spec.build_extensions
      rescue Gem::InstallError => e
        $stderr.puts e.message
      end
      exit spec.missing_extensions? ? 1 : 0
    RUBY

    module_function

    def run(spec, ui: Gem::DefaultUserInteraction.ui)
      return if spec.extensions.empty?
      # Bundler autoloads Installer, so only a real load marks bundle install.
      return if defined?(Bundler) && !Bundler.autoload?(:Installer)
      # A per-ABI base_dir is private to this ruby, so the others never read it.
      base_dir = File.realpath(spec.base_dir) rescue File.expand_path(spec.base_dir)
      return if [Gem.default_dir, Gem.user_dir].any? { |dir| (File.realpath(dir) rescue File.expand_path(dir)) == base_dir }

      env = { "GEM_HOME" => spec.base_dir, "GEM_PATH" => Gem.path.join(File::PATH_SEPARATOR) }
      # The parent's Bundler setup does not resolve under another ruby.
      %w[BUNDLER_SETUP RUBYOPT RUBYLIB RUBYGEMS_GEMDEPS BUNDLE_GEMFILE BUNDLE_BIN_PATH].each { |key| env[key] = nil }
      # The child sees Gem.path through realpath, the parent may not.
      spec_file = File.realpath(spec.spec_file) rescue spec.spec_file
      rubies.each do |name, ruby|
        system(env, ruby, "-e", BUILD, "--", spec.name, spec.version.to_s, spec_file)
        case $?.exitstatus
        when 0 then ui.say "Built #{spec.full_name} extensions for #{name}"
        when 2 then next
        else ui.alert_warning "Failed to build #{spec.full_name} extensions for #{name}"
        end
      end
    end

    # [name, path] pairs, one per distinct install, the running ruby excluded.
    def rubies
      names = ENV["GEM_REPAIR_RUBIES"]&.split(",")&.map(&:strip)
      return [] if names&.empty?

      # Gem.ruby quotes a path that contains a space, RbConfig.ruby does not.
      current = File.realpath(RbConfig.ruby)
      seen = {}
      roots.flat_map { |root, pattern| Dir.glob(pattern, base: root).sort.map { |path| File.join(root, path) } }.filter_map do |ruby|
        name = File.basename(File.dirname(File.dirname(ruby)))
        next if SKIP.match?(name)
        next if names && !names.include?(name)

        real = begin
          File.realpath(ruby)
        rescue SystemCallError
          next
        end
        next if real == current || seen[real]

        seen[real] = true
        [name, ruby]
      end
    end

    def roots
      mise = ENV["MISE_DATA_DIR"] || File.join(ENV["XDG_DATA_HOME"] || File.expand_path("~/.local/share"), "mise")
      rbenv = ENV["RBENV_ROOT"] || File.expand_path("~/.rbenv")
      # Kept apart from the pattern so metacharacters in the roots stay literal.
      [[mise, "installs/ruby/*/bin/ruby"], [rbenv, "versions/*/bin/ruby"]]
    end
  end
end
