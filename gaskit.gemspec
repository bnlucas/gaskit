# frozen_string_literal: true

require_relative "lib/gaskit/version"

Gem::Specification.new do |spec|
  spec.name          = "gaskit"
  spec.version       = Gaskit::VERSION
  spec.authors       = ["Nathan Lucas"]
  spec.email         = ["bnlucas@outlook.com"]

  spec.summary       = "Composable operation pattern with structured results and logging."
  spec.description   = "Gaskit provides a lightweight, extensible framework for encapsulating business logic " \
                       "using a consistent, composable operation pattern. It supports context propagation, exit " \
                       "handling, structured results, and flexible logging via configuration."
  spec.homepage      = "https://github.com/bnlucas/gaskit"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/bnlucas/gaskit"
  spec.metadata["changelog_uri"]   = "https://github.com/bnlucas/gaskit/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Only include files tracked by git, but exclude common dev/test files
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.start_with?(*%w[spec/ test/ features/ .git .github Gemfile Rakefile])
    end
  end

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies (add if needed)
  spec.add_dependency "railties", "~> 7.0"

  # Development dependencies
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rubocop", "~> 1.60"
  spec.add_development_dependency "yard", "~> 0.9"
end
