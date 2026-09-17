# frozen_string_literal: true

require "capistrano/mise/commands"

commands = Capistrano::Mise::Commands

namespace :mise do
  desc "Check that mise is usable on the target hosts"
  task :check do
    # Read outside the `on` block: inside it, self is the SSHKit backend, and the
    # Capistrano DSL is only reachable there because capistrano/setup includes it
    # into Object. These are settings, not per-host values.
    path = fetch(:mise_path)

    on release_roles(fetch(:mise_roles)) do |host|
      next if test commands.executable(path)

      error commands.missing_binary(path, host)
      exit 1
    end
  end

  desc "Install the tool versions this revision declares"
  task :install do
    release = release_path

    on release_roles(fetch(:mise_roles)) do
      unless test commands.config_present(release)
        warn commands.idiomatic_version_file_warning if test commands.idiomatic_version_file_present(release)
      end

      within release do
        execute :mise, :install
      end
    end
  end

  # Runs after the stage task so that stage-level `set` calls have been applied.
  task :map_bins do
    # mise installs missing tools on demand by default, which would bury a Ruby
    # build inside whichever command happened to run first. mise:install owns that.
    SSHKit.config.default_env["MISE_EXEC_AUTO_INSTALL"] = "0"

    SSHKit.config.command_map[:mise] = fetch(:mise_path)

    # unshift, so a command already carrying a prefix (capistrano-bundler's
    # `bundle exec`) keeps it and gains mise in front rather than losing it.
    prefix = commands.exec_prefix(fetch(:mise_path))
    fetch(:mise_map_bins).uniq.each do |command|
      SSHKit.config.command_map.prefix[command.to_sym].unshift(prefix)
    end
  end
end

Capistrano::DSL.stages.each do |stage|
  after stage, "mise:map_bins"
end

# These hooks need their tasks to exist, so this must be required after
# capistrano/deploy. Without the guard the failure is "Don't know how to build
# task 'deploy:check'", which names nothing you would think to look at.
unless Rake::Task.task_defined?("deploy:check")
  raise "capistrano/mise must be required after capistrano/deploy in your Capfile."
end

after "deploy:check", "mise:check"

# deploy:updating, not deploy:updated: capistrano-bundler hooks `before
# deploy:updated`, and hooks on the same task fire in registration order, which
# depends on Capfile require order. Hooking the earlier task wins regardless.
# The release is already populated by then, because git:create_release runs off
# deploy:new_release_path, a prerequisite of deploy:updating.
after "deploy:updating", "mise:install"

namespace :load do
  task :defaults do
    set :mise_path, "$HOME/.local/bin/mise"
    set :mise_roles, fetch(:mise_roles, :all)
    set :mise_map_bins, %w[rake gem bundle ruby rails]
  end
end
