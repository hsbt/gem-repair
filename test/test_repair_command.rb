# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"
require "rubygems/commands/repair_command"

class TestRepairCommand < Minitest::Test
  DLEXT = GemRepair::Sweep::DLEXT

  def setup
    @home = File.realpath(Dir.mktmpdir)
    @specs = []
    Gem::Specification.all = @specs
  end

  def teardown
    Gem::Specification.reset
    FileUtils.rm_rf(@home)
  end

  def install(name, built: true, platform: nil, depends_on: nil)
    spec = Gem::Specification.new do |s|
      s.name = name
      s.version = "1.0"
      s.summary = name
      s.authors = ["test"]
      s.extensions = ["ext/extconf.rb"]
      s.platform = platform if platform
      s.add_runtime_dependency(depends_on) if depends_on
    end
    FileUtils.mkdir_p(File.join(@home, "specifications"))
    File.write(File.join(@home, "specifications", "#{spec.full_name}.gemspec"), spec.to_ruby)
    spec = Gem::Specification.load(File.join(@home, "specifications", "#{spec.full_name}.gemspec"))
    lib = File.join(spec.full_gem_path, "lib")
    FileUtils.mkdir_p(File.join(lib, "3.3"))
    FileUtils.mkdir_p(spec.extension_dir)
    File.write(File.join(lib, "#{name}#{DLEXT}"), "")
    File.write(File.join(lib, "3.3", "#{name}#{DLEXT}"), "")
    File.write(File.join(spec.extension_dir, "#{name}#{DLEXT}"), "")
    FileUtils.touch(spec.gem_build_complete_path) if built
    @specs << spec
    Gem::Specification.all = @specs
    spec
  end

  def repair(*args)
    cmd = Gem::Commands::RepairCommand.new
    yield cmd if block_given?
    cmd.handle_options(args)
    ui = Gem::StreamUI.new(StringIO.new, StringIO.new, StringIO.new, false)
    Gem::DefaultUserInteraction.use_ui(ui) { cmd.execute }
    [ui.outs.string, ui.errs.string]
  end

  def test_sweeps_lib_copies_of_every_gem_with_extensions
    ok = install("ok")
    copy = File.join(ok.full_gem_path, "lib", "ok#{DLEXT}")

    out, = repair

    refute File.exist?(copy)
    assert File.exist?(File.join(ok.full_gem_path, "lib", "3.3", "ok#{DLEXT}"))
    assert_includes out, "Removed #{copy}"
    assert_includes out, "No gems found with missing extensions."
  end

  def test_aggressive_sweep_removes_development_directories
    ok = install("ok")
    test_dir = File.join(ok.full_gem_path, "test")
    FileUtils.mkdir_p(test_dir)

    repair
    assert File.exist?(test_dir)

    out, = repair("--aggressive-sweep")

    refute File.exist?(test_dir)
    assert_includes out, "Removed #{test_dir}"
  end

  def test_aggressive_sweep_runs_again_after_repair
    broken = install("broken", built: false)
    test_dir = File.join(broken.full_gem_path, "test")

    repair("--aggressive-sweep") do |cmd|
      cmd.define_singleton_method(:repair_gem) { |_spec| FileUtils.mkdir_p(test_dir) }
    end

    refute File.exist?(test_dir)
  end

  def test_prune_uninstalls_gems_still_missing_after_repair
    broken = install("broken", built: false)

    out, err = repair("--prune")

    assert_includes err, "Failed to repair broken-1.0"
    assert_includes out, "Successfully uninstalled broken-1.0"
    refute File.exist?(broken.full_gem_path)
    refute File.exist?(broken.spec_file)
  end

  def test_prune_uninstalls_a_gem_another_one_depends_on
    broken = install("broken", built: false)
    install("dependent", depends_on: "broken")

    out, err = repair("--prune")

    assert_includes out, "Successfully uninstalled broken-1.0"
    refute_includes err, "Uninstallation aborted"
    refute File.exist?(broken.spec_file)
  end

  def test_prune_leaves_the_same_version_for_another_platform
    broken = install("broken", built: false)
    other = install("broken", platform: "x86_64-linux")

    out, = repair("--prune")

    assert_includes out, "Successfully uninstalled broken-1.0"
    refute File.exist?(broken.spec_file)
    assert File.exist?(other.spec_file)
  end

  def test_without_prune_keeps_missing_gems
    broken = install("broken", built: false)

    repair

    assert File.exist?(broken.spec_file)
  end

  def test_dry_run_changes_nothing
    ok = install("ok")
    broken = install("broken", built: false)
    copy = File.join(ok.full_gem_path, "lib", "ok#{DLEXT}")

    out, err = repair("-n", "--prune")

    assert_empty err
    assert_includes out, "Would remove #{copy}"
    assert_includes out, "Would repair broken-1.0"
    assert_includes out, "Would uninstall broken-1.0 unless repaired"
    assert File.exist?(copy)
    assert File.exist?(broken.spec_file)
  end
end
