require_relative "lib/capistrano/mise/version"

Gem::Specification.new do |spec|
  spec.name          = "capistrano-mise"
  spec.version       = Capistrano::Mise::VERSION
  spec.authors       = ["Zac"]
  spec.summary       = "Run Capistrano's remote commands through mise"
  spec.description   = "Wraps the commands Capistrano runs on a host with `mise exec`, so they " \
                       "resolve their tool versions from the mise config that shipped with the revision."
  spec.homepage      = "https://github.com/7a6163/capistrano-mise"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir["lib/**/*", "README.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["github_repo"] = "ssh://github.com/7a6163/capistrano-mise"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.add_dependency "capistrano", "~> 3.0"
end
