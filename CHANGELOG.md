# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-09-18

First release.

### Added
- Wraps the commands Capistrano runs on a host with `mise exec --`, pushed onto the
  front of SSHKit's per-command prefix list so that a prefix another plugin
  contributed — `capistrano-bundler`'s `bundle exec` — still applies.
- `mise:check`, after `deploy:check`, which stops the deploy if mise is not
  executable where `:mise_path` says it is.
- `mise:install`, after `deploy:updating`, which runs `mise install` in the new
  release. It installs the tools mise manages, not mise itself.
- Settings: `:mise_path` (default `$HOME/.local/bin/mise`), `:mise_map_bins`
  (default `%w[rake gem bundle ruby rails]`) and `:mise_roles` (default `:all`).
- `MISE_EXEC_AUTO_INSTALL=0`, so a missing tool surfaces as a failure from
  `mise:install` rather than as a silent multi-minute build inside an unrelated
  command.
- A warning when a release carries an idiomatic version file such as
  `.ruby-version` but no mise config of its own, since mise does not read those
  unless you opt in per tool.
- A clear error when `capistrano/mise` is required before `capistrano/deploy`,
  in place of rake's "Don't know how to build task 'deploy:check'".

### Design notes
- There is deliberately no setting naming a version. The mise config that shipped
  with the revision is the only source of truth; use mise's own per-environment
  config files to vary it per host.
- Commands that do not reach the host through Capistrano — a systemd unit's
  `ExecStart`, a crontab entry — are outside this plugin's reach and need their
  own arrangement. The README has the shapes that work.
- `mise exec` rather than shims or shell activation. Capistrano's SSH connection
  gets a non-interactive, non-login shell, which reads no profile at all, and
  mise's activation recomputes the environment when a prompt is displayed — which
  never happens here. `mise exec` with an absolute path needs neither, and unlike
  shims it does not require writing to a shared `PATH`.

### Internal
- The shell fragments live in `Capistrano::Mise::Commands`, apart from the rake
  file, which cannot be loaded outside a Capfile. They are covered by mutation
  testing at 100%, enforced in CI.
- Tasks are covered at the seam that matters for a Capistrano plugin: the
  commands a task sends to a host, recorded through a stub SSHKit backend.
- Settings are read outside the `on` block. Inside one, `self` is the SSHKit
  backend, and the Capistrano DSL is reachable there only because
  `capistrano/setup` includes it into `Object`.

[Unreleased]: https://github.com/7a6163/capistrano-mise/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/7a6163/capistrano-mise/releases/tag/v0.1.0
