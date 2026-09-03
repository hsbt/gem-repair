# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "gem_repair/fanout"

class TestPlugin < Minitest::Test
  LIB = File.expand_path("../lib", __dir__)
  CHECK = '2.times { load "rubygems_plugin.rb" }; ' \
          'print Gem.post_install_hooks.size, " ", Gem::CommandManager.instance.command_names.include?("repair")'

  def test_this_ruby_registers_the_hook
    assert_equal "1 true", load_plugin(RbConfig.ruby)
  end

  def test_a_ruby_below_the_required_version_gets_the_command_without_the_hook
    ruby = old_ruby
    skip "no ruby older than 2.7 installed" unless ruby

    assert_equal "0 true", load_plugin(ruby)
  end

  private

  # An empty GEM_HOME keeps the ambient plugins out of the hook count.
  def load_plugin(ruby)
    Dir.mktmpdir do |home|
      env = { "GEM_HOME" => home, "GEM_PATH" => home }
      %w[RUBYOPT RUBYLIB BUNDLER_SETUP BUNDLE_GEMFILE BUNDLE_BIN_PATH].each { |key| env[key] = nil }
      IO.popen([env, ruby, "-I#{LIB}", "-e", CHECK], err: File::NULL) { |io| io.read }
    end
  end

  # The newest one below the guard, so the check is not about a ruby nobody runs.
  def old_ruby
    installed = GemRepair::Fanout.roots.flat_map { |root, pattern| Dir.glob(pattern, base: root).map { |path| File.join(root, path) } }.filter_map do |path|
      name = File.basename(File.dirname(File.dirname(path)))
      [Gem::Version.new(name), path] if name.match?(/\A\d+(\.\d+)+\z/)
    end
    installed.select { |version, _| version < Gem::Version.new("2.7") }.max&.last
  end
end
