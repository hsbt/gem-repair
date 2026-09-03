# frozen_string_literal: true

require "rbconfig"
require "fileutils"

module GemRepair
  # Removes the copies of built extensions that RubyGems leaves in the gem's
  # lib next to the per-ABI copy under extensions/. lib comes first on the
  # load path, so every other ruby sharing the GEM_HOME would load the copy
  # built for the installing ruby and fail. RubyGems 3.6 added a gemrc setting
  # to skip the copy, but it stays on by default.
  module Sweep
    DLEXT = ".#{RbConfig::CONFIG["DLEXT"]}"


    # What gem sweep --aggressive removed on top of the extension copies.
    DEVELOPMENT = %w[test spec features]

    module_function

    def targets(spec)
      return [] if spec.default_gem? || spec.extensions.empty?

      # RubyGems copies one tree into both extensions/ and lib, so a file with
      # no counterpart under extensions/ was shipped by the gem itself.
      built = Dir.glob(File.join("*", "*", spec.full_name, "**", "*#{DLEXT}"), base: File.join(spec.base_dir, "extensions"))
      built = built.map { |file| file.split("/", 4).last }
      (spec.full_require_paths - [spec.extension_dir]).flat_map do |path|
        Dir.glob(File.join("**", "*#{DLEXT}"), base: path).select { |file| built.include?(file) }.map { |file| File.join(path, file) }
      end
    end

    def development_targets(spec)
      return [] if spec.default_gem?

      root = spec.full_gem_path
      dirs = DEVELOPMENT.map { |dir| File.join(root, dir) } + Dir.glob("**/tmp", base: root).map { |tmp| File.join(root, tmp) }
      dirs.select { |dir| File.directory?(dir) && dirs.none? { |other| dir.start_with?("#{other}/") } }
    end

    def clean(spec, dry_run: false, aggressive: false, ui: Gem::DefaultUserInteraction.ui)
      paths = targets(spec)
      paths += development_targets(spec) if aggressive
      paths.each do |path|
        if dry_run
          ui.say "Would remove #{path}"
        else
          File.directory?(path) ? FileUtils.rm_r(path) : File.delete(path)
          ui.say "Removed #{path}"
        end
      rescue SystemCallError => e
        ui.alert_warning "Could not remove #{path}: #{e.message}"
      end
    end
  end
end
