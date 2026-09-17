# frozen_string_literal: true

require "minitest/autorun"
require "capistrano/all"

# capistrano/setup does this at the top level, which is what makes
# Capistrano::DSL.stages (used by the rake file) resolve. Doing it here keeps
# the test from pulling in setup, which would go looking for a deploy config.
include Capistrano::DSL

# mise.rake hooks deploy:check and deploy:updating, so those tasks have to be
# defined first - the same ordering a Capfile already uses.
require "capistrano/deploy"
require "capistrano/mise"

# The only logic here worth a test is how the mise prefix lands in SSHKit's
# command map: that it is applied to the mapped bins, that it composes with a
# prefix another plugin already put there rather than replacing it, and that it
# is read after stage-level `set` calls rather than from the defaults.
class MiseMapBinsTest < Minitest::Test
  include Capistrano::DSL

  def setup
    Rake.application.options.trace = nil
    SSHKit.config.command_map = SSHKit::CommandMap.new
    SSHKit.config.default_env = {}
    env.set(:mise_path, "$HOME/.local/bin/mise")
    env.set(:mise_roles, :all)
    env.set(:mise_map_bins, %w[rake gem bundle ruby rails])
  end

  def map_bins
    Rake::Task["mise:map_bins"].reenable
    Rake::Task["mise:map_bins"].invoke
  end

  def test_mapped_bins_run_through_mise_exec
    map_bins

    assert_equal "$HOME/.local/bin/mise exec -- bundle", SSHKit.config.command_map[:bundle]
    assert_equal "$HOME/.local/bin/mise exec -- rake", SSHKit.config.command_map[:rake]
  end

  def test_unmapped_bins_are_left_alone
    map_bins

    # /usr/bin/env is SSHKit's own default; the point is that mise is absent.
    assert_equal "/usr/bin/env yarn", SSHKit.config.command_map[:yarn]
  end

  def test_mise_itself_is_callable_without_a_prefix
    map_bins

    assert_equal "$HOME/.local/bin/mise", SSHKit.config.command_map[:mise]
  end

  # capistrano-bundler prefixes :rake with `bundle exec`. mise has to end up in
  # front of that, not instead of it.
  def test_it_composes_with_a_prefix_another_plugin_already_added
    SSHKit.config.command_map.prefix[:rake].unshift("bundle exec")

    map_bins

    assert_equal "$HOME/.local/bin/mise exec -- bundle exec rake", SSHKit.config.command_map[:rake]
  end

  def test_it_reads_mise_path_when_the_task_runs_not_when_it_was_defined
    env.set(:mise_path, "/usr/bin/mise")

    map_bins

    assert_equal "/usr/bin/mise exec -- ruby", SSHKit.config.command_map[:ruby]
  end

  def test_it_turns_off_mise_s_own_install_on_demand
    map_bins

    assert_equal "0", SSHKit.config.default_env["MISE_EXEC_AUTO_INSTALL"]
  end
end

# Seam: the commands a task sends to a host. A task's observable behaviour is the
# sequence of commands it emits and how it reacts to their exit statuses, so this
# backend records them and lets a test decide which ones fail.
class RecordingBackend < SSHKit::Backend::Abstract
  class << self
    attr_accessor :commands, :failing

    def reset!(failing: [])
      self.commands = []
      self.failing = failing
    end
  end

  def upload!(*); end
  def download!(*); end

  private

  def execute_command(cmd)
    line = cmd.to_command
    self.class.commands << line
    cmd.exit_status = self.class.failing.any? { |pattern| line.match?(pattern) } ? 1 : 0
  end
end

# `warn` and `error` inside an `on` block are delegated to SSHKit's output.
class RecordingOutput
  attr_reader :messages

  def initialize
    @messages = []
  end

  # warn, error and friends have to be declared rather than caught by
  # method_missing: Kernel already defines private versions of them, so they
  # resolve there and the message goes to stderr instead of being recorded.
  %i[log fatal error warn info debug].each do |level|
    define_method(level) do |message = nil, *|
      @messages << message.to_s
      nil
    end
  end

  def method_missing(_name, *args)
    @messages << args.first.to_s
    nil
  end

  def respond_to_missing?(*)
    true
  end
end

class MiseTaskTest < Minitest::Test
  include Capistrano::DSL

  RELEASE = "/var/www/app/releases/20260101000000".freeze

  def setup
    Capistrano::Configuration.reset!
    Rake::Task.tasks.each(&:reenable)
    Rake.application.options.trace = nil

    RecordingBackend.reset!
    @output = RecordingOutput.new
    SSHKit.config.backend = RecordingBackend
    SSHKit.config.output = @output

    server "example.com", roles: %w[app]
    set :mise_path, "$HOME/.local/bin/mise"
    set :mise_roles, :all
    set :mise_map_bins, %w[rake gem bundle ruby rails]
    set :release_path, Pathname.new(RELEASE)
  end

  def commands
    RecordingBackend.commands
  end

  def messages
    @output.messages.join("\n")
  end

  def test_check_aborts_the_deploy_when_mise_is_not_executable
    RecordingBackend.reset!(failing: [/-x /])

    assert_raises(SystemExit) { Rake::Task["mise:check"].invoke }
  end

  def test_check_lets_the_deploy_continue_when_mise_is_executable
    Rake::Task["mise:check"].invoke

    assert_includes commands.join("\n"), "-x $HOME/.local/bin/mise"
  end

  # map_bins is what teaches SSHKit where mise lives, and in a deploy it has run
  # (off the stage task) long before install does.
  def install_after_map_bins
    Rake::Task["mise:map_bins"].invoke
    Rake::Task["mise:install"].invoke
  end

  def test_install_runs_mise_install_inside_the_release
    install_after_map_bins

    install = commands.find { |line| line.include?("mise install") }
    assert install, "no mise install command was sent"
    assert_includes install, "cd #{RELEASE} &&"
    assert_includes install, "$HOME/.local/bin/mise install"
  end

  # SSHKit skips `within` for any command given as a string with whitespace, so a
  # probe that relies on it silently inspects the SSH login directory instead.
  def test_install_looks_for_config_in_the_release_not_the_login_directory
    install_after_map_bins

    probe = commands.find { |line| line.include?(".tool-versions") }
    assert probe, "no config probe was sent"
    assert_includes probe, "#{RELEASE}/.tool-versions"
  end

  # Failing every probe that names a mise config file is how this says "the
  # release carries none of them".
  NO_MISE_CONFIG = [/mise\.toml/].freeze

  def test_install_warns_when_the_release_carries_only_a_ruby_version_file
    RecordingBackend.reset!(failing: NO_MISE_CONFIG)

    install_after_map_bins

    assert_includes messages, "idiomatic version files"
  end

  def test_install_stays_quiet_when_the_release_carries_a_mise_config
    install_after_map_bins

    refute_includes messages, "idiomatic version files"
  end

  # From mise's configuration docs, not from the implementation: this list is the
  # independent source of truth, and an earlier version of the probe named only
  # three of these, so a release using .config/mise.toml was wrongly warned about.
  MISE_CONFIG_FILENAMES = %w[
    mise.toml mise.local.toml .mise.toml .mise.local.toml
    mise/config.toml .mise/config.toml
    .config/mise.toml .config/mise/config.toml
    .tool-versions
  ].freeze

  def test_install_probes_for_every_config_filename_mise_reads
    install_after_map_bins

    probe = commands.find { |line| line.include?(".tool-versions") }

    MISE_CONFIG_FILENAMES.each do |filename|
      assert_includes probe, "-e #{RELEASE}/#{filename}", "probe does not look for #{filename}"
    end
  end
end
