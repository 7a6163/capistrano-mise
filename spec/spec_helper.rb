# frozen_string_literal: true

require "capistrano/all"

# The rake file calls Capistrano::DSL.stages. That resolves in a real Capfile only
# because capistrano/setup does a top-level `include Capistrano::DSL`, which lands
# on Object and so reaches the module object too. Doing that here would give every
# object in the suite - String included - methods named any?, fetch, set and
# server, so extend the module itself and leave Object alone.
Capistrano::DSL.extend(Capistrano::DSL)

# mise.rake hooks deploy:check and deploy:updating, so those tasks have to be
# defined first - the same ordering a Capfile already uses.
require "capistrano/deploy"
require "capistrano/mise"

# Seam: the commands a task sends to a host. A task's observable behaviour is the
# sequence of commands it emits and how it reacts to their exit statuses, so this
# backend records them and lets an example decide which ones fail.
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

  # warn, error and friends have to be declared rather than caught by
  # method_missing: Kernel already defines private versions of them, so they
  # resolve there and the message goes to stderr instead of being recorded.
  %i[log fatal error warn info debug].each do |level|
    define_method(level) do |message = nil, *|
      messages << message.to_s
      nil
    end
  end

  def initialize
    @messages = []
  end

  def method_missing(_name, *args)
    messages << args.first.to_s
    nil
  end

  def respond_to_missing?(*)
    true
  end
end

RSpec.configure do |config|
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
