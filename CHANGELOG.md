# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-09-17
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

### Notes
- There is deliberately no setting naming a version. The mise config that shipped
  with the revision is the only source of truth; use mise's own per-environment
  config files to vary it per host.
- Commands that do not reach the host through Capistrano — a systemd unit's
  `ExecStart`, a crontab entry — are outside this plugin's reach and need their
  own arrangement. The README has the shapes that work.

[Unreleased]: https://github.com/7a6163/capistrano-mise/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/7a6163/capistrano-mise/releases/tag/v0.1.0
