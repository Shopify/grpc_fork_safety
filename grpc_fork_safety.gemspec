# frozen_string_literal: true

require_relative "lib/grpc_fork_safety/version"

Gem::Specification.new do |spec|
  spec.name = "grpc_fork_safety"
  spec.version = GrpcForkSafety::VERSION
  spec.authors = ["Jean Boussier"]
  spec.email = ["jean.boussier@gmail.com"]

  spec.summary = "Simple gems to facilitate making the grpc gem fork safe"
  spec.required_ruby_version = ">= 3.1.0" # When `Process._fork` was added

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.homepage = "https://github.com/Shopify/grpc_fork_safety"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "grpc", ">= 1.57.0" # When GRPC.prefork was added
end
