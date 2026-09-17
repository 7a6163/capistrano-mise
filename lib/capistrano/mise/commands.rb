# frozen_string_literal: true

module Capistrano
  module Mise
    # The shell fragments this plugin sends to a host. Kept apart from the rake
    # file so they can be loaded, read and mutated on their own: requiring the
    # rake file outside a Capfile is not possible, because it hooks tasks that
    # only exist once capistrano/deploy has been loaded.
    module Commands
      # Every filename mise looks for in a single directory, from mise's
      # configuration docs. mise also searches parent directories and a global
      # config, so a release holding none of these can still resolve a version.
      CONFIG_FILENAMES = %w[
        mise.toml mise.local.toml .mise.toml .mise.local.toml
        mise/config.toml .mise/config.toml
        .config/mise.toml .config/mise/config.toml
        .tool-versions
      ].freeze

      # mise reads idiomatic version files only when opted in per tool, so a
      # release carrying this and nothing else resolves no version at all.
      IDIOMATIC_VERSION_FILE = ".ruby-version"

      # extend self, not module_function: module_function copies each method onto
      # the module's singleton, so a mutation to the instance method would leave
      # the copy that callers actually reach untouched, and mutant would report
      # coverage this module does not have.
      extend self

      # Goes in front of a mapped command. `--` ends mise's own arguments, so a
      # command that starts with a dash is not read as one of them.
      def exec_prefix(mise_path)
        "#{mise_path} exec --"
      end

      def executable(path)
        "[ -x #{path} ]"
      end

      def any_exist(paths)
        "[ #{paths.map { |path| "-e #{path}" }.join(' -o ')} ]"
      end

      # Spelled out against the release rather than run inside SSHKit's `within`:
      # SSHKit hands a string command containing whitespace straight to the shell,
      # with no cd and no env, so a relative probe would silently inspect the SSH
      # login directory instead.
      def config_present(release_path)
        any_exist(CONFIG_FILENAMES.map { |name| File.join(release_path, name) })
      end

      def idiomatic_version_file_present(release_path)
        any_exist([File.join(release_path, IDIOMATIC_VERSION_FILE)])
      end

      def missing_binary(path, host)
        "mise is not executable at #{path} on #{host}. Install mise, " \
          "or set :mise_path if it is installed somewhere else on this host."
      end

      def idiomatic_version_file_warning
        "this revision has #{IDIOMATIC_VERSION_FILE} but no mise config of its own. mise does " \
          "not read idiomatic version files unless you opt in, so unless a parent directory or " \
          "the global config supplies one, no Ruby version resolves here. Add a mise.toml or " \
          ".tool-versions, or run: mise settings add idiomatic_version_file_enable_tools ruby"
      end
    end
  end
end
