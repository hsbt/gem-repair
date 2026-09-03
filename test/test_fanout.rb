# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "gem_repair/fanout"

class TestFanout < Minitest::Test
  Ui = Struct.new(:said, :warned) do
    def say(msg)
      said << msg
    end

    def alert_warning(msg)
      warned << msg
    end
  end

  def setup
    @dir = Dir.mktmpdir
    @env = ENV.to_h.slice("MISE_DATA_DIR", "RBENV_ROOT", "GEM_REPAIR_RUBIES")
    ENV["MISE_DATA_DIR"] = File.join(@dir, "mise")
    ENV["RBENV_ROOT"] = File.join(@dir, "rbenv")
    ENV.delete("GEM_REPAIR_RUBIES")
  end

  def teardown
    %w[MISE_DATA_DIR RBENV_ROOT GEM_REPAIR_RUBIES].each { |k| ENV.delete(k) }
    ENV.update(@env)
    FileUtils.rm_rf(@dir)
  end

  def fake_ruby(manager, name, exit_code = 0)
    sub = manager == "mise" ? "installs/ruby" : "versions"
    bin = File.join(@dir, manager, sub, name, "bin")
    FileUtils.mkdir_p(bin)
    path = File.join(bin, "ruby")
    File.write(path, "#!/bin/sh\necho \"$@\" > \"#{@dir}/#{name}.args\"\nenv > \"#{@dir}/#{name}.env\"\nexit #{exit_code}\n")
    File.chmod(0o755, path)
    path
  end

  def spec
    Gem::Specification.new do |s|
      s.name = "ext"
      s.version = "1.0"
      s.extensions = ["ext/extconf.rb"]
      s.loaded_from = File.join(@dir, "home", "specifications", "ext-1.0.gemspec")
    end
  end

  def test_rubies_from_both_managers
    fake_ruby("mise", "3.3-dev")
    fake_ruby("rbenv", "3.4.5")

    assert_equal %w[3.3-dev 3.4.5], GemRepair::Fanout.rubies.map(&:first)
  end

  def test_rubies_skip_other_engines_and_duplicates
    real = fake_ruby("mise", "3.3-dev")
    fake_ruby("mise", "jruby-10.1.0.0")
    File.symlink(File.dirname(File.dirname(real)), File.join(@dir, "mise/installs/ruby/3.3.5"))

    assert_equal %w[3.3-dev], GemRepair::Fanout.rubies.map(&:first)
  end

  def test_rubies_under_a_root_with_glob_metacharacters
    ENV["RBENV_ROOT"] = File.join(@dir, "rb[e]nv")
    fake_ruby("rb[e]nv", "3.3-dev")

    assert_equal %w[3.3-dev], GemRepair::Fanout.rubies.map(&:first)
  end

  def test_rubies_skip_running_ruby
    FileUtils.mkdir_p(File.join(@dir, "mise/installs/ruby/current"))
    File.symlink(File.dirname(RbConfig.ruby), File.join(@dir, "mise/installs/ruby/current/bin"))

    assert_empty GemRepair::Fanout.rubies
  end

  def test_rubies_skip_dangling_ruby
    fake_ruby("mise", "3.3-dev")
    bin = File.join(@dir, "mise/installs/ruby/broken/bin")
    FileUtils.mkdir_p(bin)
    File.symlink(File.join(@dir, "gone"), File.join(bin, "ruby"))

    assert_equal %w[3.3-dev], GemRepair::Fanout.rubies.map(&:first)
  end

  def test_rubies_filtered_by_env
    fake_ruby("mise", "3.3-dev")
    fake_ruby("mise", "3.4-dev")

    ENV["GEM_REPAIR_RUBIES"] = "3.4-dev, 4.0-dev"
    assert_equal %w[3.4-dev], GemRepair::Fanout.rubies.map(&:first)

    ENV["GEM_REPAIR_RUBIES"] = ""
    assert_empty GemRepair::Fanout.rubies
  end

  def test_run_builds_in_each_ruby
    fake_ruby("mise", "ok")
    fake_ruby("mise", "noop", 2)
    fake_ruby("mise", "bad", 1)
    ui = Ui.new([], [])
    gem = spec

    GemRepair::Fanout.run(gem, ui: ui)

    assert_equal ["Built ext-1.0 extensions for ok"], ui.said
    assert_equal ["Failed to build ext-1.0 extensions for bad"], ui.warned
    assert_equal "-e #{GemRepair::Fanout::BUILD} -- ext 1.0 #{gem.spec_file}", File.read(File.join(@dir, "ok.args")).chomp
  end

  def test_run_drops_the_parent_bundler_environment
    fake_ruby("mise", "ok")
    saved = ENV.to_h.slice("RUBYOPT", "BUNDLER_SETUP")
    ENV["RUBYOPT"] = "-rbundler/setup"
    ENV["BUNDLER_SETUP"] = "/nowhere/bundler/setup"

    GemRepair::Fanout.run(spec, ui: Ui.new([], []))

    refute_match(/^(RUBYOPT|BUNDLER_SETUP)=/, File.read(File.join(@dir, "ok.env")))
  ensure
    %w[RUBYOPT BUNDLER_SETUP].each { |k| ENV.delete(k) }
    ENV.update(saved) if saved
  end

  def test_run_skips_per_abi_directories
    fake_ruby("mise", "ok")

    [Gem.default_dir, Gem.user_dir].each do |dir|
      private_gem = spec
      private_gem.loaded_from = File.join(dir, "specifications", "ext-1.0.gemspec")

      GemRepair::Fanout.run(private_gem, ui: Ui.new([], []))

      refute File.exist?(File.join(@dir, "ok.args")), "fanned out into #{dir}"
    end
  end

  def test_run_skips_gems_without_extensions
    fake_ruby("mise", "ok")
    plain = spec
    plain.extensions = []

    GemRepair::Fanout.run(plain, ui: Ui.new([], []))

    refute File.exist?(File.join(@dir, "ok.args"))
  end
end
