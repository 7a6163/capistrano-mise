# frozen_string_literal: true

RSpec.describe "mise tasks" do
  include Capistrano::DSL

  release = "/var/www/app/releases/20260101000000"

  def invoke(name)
    Rake::Task[name].invoke
  end

  def commands
    RecordingBackend.commands
  end

  def messages
    @output.messages.join("\n")
  end

  before do
    Capistrano::Configuration.reset!
    Rake::Task.tasks.each(&:reenable)
    Rake.application.options.trace = nil

    RecordingBackend.reset!
    @output = RecordingOutput.new
    SSHKit.config.backend = RecordingBackend
    SSHKit.config.output = @output
    SSHKit.config.command_map = SSHKit::CommandMap.new
    SSHKit.config.default_env = {}

    server "example.com", roles: %w[app]
    set :mise_path, "$HOME/.local/bin/mise"
    set :mise_roles, :all
    set :mise_map_bins, %w[rake gem bundle ruby rails]
    set :release_path, Pathname.new(release)
  end

  describe "mise:map_bins" do
    it "runs the mapped commands through mise" do
      invoke("mise:map_bins")

      expect(SSHKit.config.command_map[:bundle]).to eq("$HOME/.local/bin/mise exec -- bundle")
    end

    it "leaves commands outside :mise_map_bins alone" do
      invoke("mise:map_bins")

      # /usr/bin/env is SSHKit's own default; the point is that mise is absent.
      expect(SSHKit.config.command_map[:yarn]).to eq("/usr/bin/env yarn")
    end

    it "makes mise itself callable without wrapping it in itself" do
      invoke("mise:map_bins")

      expect(SSHKit.config.command_map[:mise]).to eq("$HOME/.local/bin/mise")
    end

    # capistrano-bundler prefixes :rake with `bundle exec`. mise has to end up in
    # front of that, not instead of it.
    it "keeps a prefix another plugin already added" do
      SSHKit.config.command_map.prefix[:rake].unshift("bundle exec")

      invoke("mise:map_bins")

      expect(SSHKit.config.command_map[:rake]).to eq("$HOME/.local/bin/mise exec -- bundle exec rake")
    end

    it "reads :mise_path when it runs, so a stage can override it" do
      set :mise_path, "/usr/bin/mise"

      invoke("mise:map_bins")

      expect(SSHKit.config.command_map[:ruby]).to eq("/usr/bin/mise exec -- ruby")
    end

    it "turns off mise's own install-on-demand" do
      invoke("mise:map_bins")

      expect(SSHKit.config.default_env["MISE_EXEC_AUTO_INSTALL"]).to eq("0")
    end
  end

  describe "mise:check" do
    it "aborts the deploy when mise is not executable" do
      RecordingBackend.reset!(failing: [/-x /])

      expect { invoke("mise:check") }.to raise_error(SystemExit)
    end

    it "lets the deploy continue when mise is executable" do
      invoke("mise:check")

      expect(commands.join("\n")).to include("-x $HOME/.local/bin/mise")
    end
  end

  describe "mise:install" do
    # map_bins is what teaches SSHKit where mise lives, and in a deploy it has run
    # (off the stage task) long before install does.
    def install
      invoke("mise:map_bins")
      invoke("mise:install")
    end

    # Failing every probe that names a mise config file is how this says "the
    # release carries none of them".
    no_mise_config = [/mise\.toml/].freeze

    it "runs mise install inside the release" do
      install

      expect(commands).to include(a_string_including("cd #{release} &&").and(a_string_including("mise install")))
    end

    # SSHKit skips `within` for any command given as a string with whitespace, so
    # a probe that relied on it would silently inspect the SSH login directory.
    it "looks for config in the release, not the login directory" do
      install

      probe = commands.find { |line| line.include?(".tool-versions") }
      expect(probe).to include("#{release}/.tool-versions")
    end

    it "warns when the release carries only a .ruby-version" do
      RecordingBackend.reset!(failing: no_mise_config)

      install

      expect(messages).to include("idiomatic version files")
    end

    it "stays quiet when the release carries a mise config" do
      install

      expect(messages).not_to include("idiomatic version files")
    end

    it "does not even ask about .ruby-version when a mise config is there" do
      install

      expect(commands).not_to include(a_string_including(".ruby-version"))
    end
  end
end
