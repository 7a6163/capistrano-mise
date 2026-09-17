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
    on release_roles(fetch(:mise_roles)) do |host|
      within release_path do
        if !test("[ -e mise.toml -o -e .mise.toml -o -e .tool-versions ]") && test("[ -e .ruby-version ]")
          warn "#{host}: this revision has .ruby-version but no mise config. mise does not read " \
               "idiomatic version files unless you opt in, so it will resolve no Ruby version here. " \
               "Add a mise.toml or .tool-versions, or run: " \
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
