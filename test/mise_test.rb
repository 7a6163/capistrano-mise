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
