# frozen_string_literal: true

RSpec.describe Capistrano::Mise::Commands do
  let(:release) { Pathname.new("/var/www/app/releases/20260101000000") }

  describe ".exec_prefix" do
    it "runs the command under mise, with -- ending mise's own arguments" do
      expect(described_class.exec_prefix("/usr/bin/mise")).to eq("/usr/bin/mise exec --")
    end
  end

  describe ".executable" do
    it "asks whether the path is executable" do
      expect(described_class.executable("/usr/bin/mise")).to eq("[ -x /usr/bin/mise ]")
    end
  end

  describe ".any_exist" do
    it "asks about a single path" do
      expect(described_class.any_exist(["/tmp/one"])).to eq("[ -e /tmp/one ]")
    end

    it "joins several paths with -o, so any one of them is enough" do
      expect(described_class.any_exist(["/tmp/one", "/tmp/two"]))
        .to eq("[ -e /tmp/one -o -e /tmp/two ]")
    end
  end

  describe ".config_present" do
    subject(:probe) { described_class.config_present(release) }

    # The list comes from mise's configuration docs rather than from the
    # implementation. An earlier version named only three of these, so a release
    # using .config/mise.toml was warned about for no reason.
    %w[
      mise.toml mise.local.toml .mise.toml .mise.local.toml
      mise/config.toml .mise/config.toml
      .config/mise.toml .config/mise/config.toml
      .tool-versions
    ].each do |filename|
      it "looks for #{filename} inside the release" do
        expect(probe).to include("-e #{release}/#{filename}")
      end
    end

    it "looks nowhere but inside the release" do
      expect(probe.scan(%r{-e (\S+)}).flatten).to all(start_with("#{release}/"))
    end

    it "asks about every filename in one test expression" do
      expect(probe).to start_with("[ ").and end_with(" ]")
    end
  end

  describe ".idiomatic_version_file_present" do
    it "asks only about .ruby-version, inside the release" do
      expect(described_class.idiomatic_version_file_present(release))
        .to eq("[ -e #{release}/.ruby-version ]")
    end
  end

  describe ".missing_binary" do
    subject(:message) { described_class.missing_binary("/usr/bin/mise", "web1.example.com") }

    it "names the path that was looked at" do
      expect(message).to include("/usr/bin/mise")
    end

    it "names the host it was looked at on" do
      expect(message).to include("web1.example.com")
    end

    it "points at the setting that moves the search" do
      expect(message).to include(":mise_path")
    end
  end

  describe ".idiomatic_version_file_warning" do
    subject(:message) { described_class.idiomatic_version_file_warning }

    it "says which file was found" do
      expect(message).to include(".ruby-version")
    end

    it "explains that mise ignores idiomatic version files by default" do
      expect(message).to include("idiomatic version files unless you opt in")
    end

    it "gives both ways out" do
      expect(message).to include("mise.toml").and include("idiomatic_version_file_enable_tools ruby")
    end
  end
end
