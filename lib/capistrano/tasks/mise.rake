namespace :mise do
  desc "Check that mise is usable on the target hosts"
  task :check do
    on release_roles(fetch(:mise_roles)) do |host|
      mise = fetch(:mise_path)
      next if test "[ -x #{mise} ]"

      error "mise is not executable at #{mise} on #{host}. Install mise, " \
            "or set :mise_path if it is installed somewhere else on this host."
      exit 1
    end
  end

  desc "Install the tool versions this revision declares"
  task :install do
    # Every filename mise looks for in one directory. It also searches parent
    # directories and a global config, so a release holding none of these can still
    # resolve a version - which is why their absence is a warning, not an error.
    config_files = %w[
      mise.toml mise.local.toml .mise.toml .mise.local.toml
      mise/config.toml .mise/config.toml
      .config/mise.toml .config/mise/config.toml
      .tool-versions
    ]

    on release_roles(fetch(:mise_roles)) do
      within release_path do
        has_config = test("[ #{config_files.map { |f| "-e #{f}" }.join(' -o ')} ]")

        if !has_config && test("[ -e .ruby-version ]")
          warn "this revision has .ruby-version but no mise config of its own. mise does not " \
               "read idiomatic version files unless you opt in, so unless a parent directory " \
               "or the global config supplies one, no Ruby version resolves here. Add a " \
               "mise.toml or .tool-versions, or run: " \
               "mise settings add idiomatic_version_file_enable_tools ruby"
        end

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
    prefix = "#{fetch(:mise_path)} exec --"
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
