# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "gem_repair/sweep"

class TestSweep < Minitest::Test
  Ui = Struct.new(:said, :warned) do
    def say(msg)
      said << msg
    end

    def alert_warning(msg)
      warned << msg
    end
  end

  DLEXT = GemRepair::Sweep::DLEXT

  def setup
    @tmp = File.realpath(Dir.mktmpdir)
    @home = File.join(@tmp, "g[e]m")
    @ui = Ui.new([], [])
  end

  def teardown
    FileUtils.rm_rf(@tmp)
  end

  def install(name = "ext", extensions: ["ext/extconf.rb"])
    spec = Gem::Specification.new do |s|
      s.name = name
      s.version = "1.0"
      s.extensions = extensions
    end
    spec.loaded_from = File.join(@home, "specifications", "#{spec.full_name}.gemspec")
    lib = File.join(spec.full_gem_path, "lib")
    FileUtils.mkdir_p(File.join(lib, "3.3"))
    FileUtils.mkdir_p(spec.extension_dir)
    File.write(File.join(lib, "#{name}.rb"), "")
    File.write(File.join(lib, "#{name}#{DLEXT}"), "")
    File.write(File.join(lib, "3.3", "#{name}#{DLEXT}"), "")
    File.write(File.join(spec.extension_dir, "#{name}#{DLEXT}"), "")
    spec
  end

  def test_targets_only_unversioned_dlext_under_lib
    spec = install

    assert_equal [File.join(spec.full_gem_path, "lib", "ext#{DLEXT}")], GemRepair::Sweep.targets(spec)
  end

  def test_targets_skip_files_without_a_built_counterpart
    spec = install
    vendored = File.join(spec.full_gem_path, "lib", "vendored#{DLEXT}")
    File.write(vendored, "")

    refute_includes GemRepair::Sweep.targets(spec), vendored
  end

  def test_targets_skip_gems_without_extensions_and_default_gems
    assert_empty GemRepair::Sweep.targets(install("plain", extensions: []))

    dflt = install("dflt")
    dflt.define_singleton_method(:default_gem?) { true }
    assert_empty GemRepair::Sweep.targets(dflt)
  end

  def test_clean_removes_targets
    spec = install
    copy = File.join(spec.full_gem_path, "lib", "ext#{DLEXT}")

    GemRepair::Sweep.clean(spec, ui: @ui)

    refute File.exist?(copy)
    assert File.exist?(File.join(spec.full_gem_path, "lib", "3.3", "ext#{DLEXT}"))
    assert File.exist?(File.join(spec.extension_dir, "ext#{DLEXT}"))
    assert_equal ["Removed #{copy}"], @ui.said
  end

  def test_clean_dry_run_keeps_targets
    spec = install
    copy = File.join(spec.full_gem_path, "lib", "ext#{DLEXT}")

    GemRepair::Sweep.clean(spec, dry_run: true, ui: @ui)

    assert File.exist?(copy)
    assert_equal ["Would remove #{copy}"], @ui.said
  end
end
