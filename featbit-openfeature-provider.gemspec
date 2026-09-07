# frozen_string_literal: true

require_relative "lib/featbit/openfeature/version"

source_code_uri = "https://github.com/featbit/openfeature-provider-ruby-server"

Gem::Specification.new do |spec|
  spec.name = "featbit-openfeature-provider"
  spec.version = FeatBit::OpenFeature::VERSION
  spec.authors = ["FeatBit"]
  spec.email = ["contact@featbit.co"]
  spec.summary = "FeatBit OpenFeature provider for Ruby server applications"
  spec.description = "Evaluate FeatBit feature flags through the OpenFeature Ruby SDK."
  spec.homepage = "https://www.featbit.co/"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.4"
  spec.metadata["source_code_uri"] = source_code_uri
  spec.metadata["bug_tracker_uri"] = "#{source_code_uri}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE", "CHANGELOG.md"]
  spec.require_paths = ["lib"]
  spec.add_dependency "featbit-server-sdk", "~> 0.1.0"
  spec.add_dependency "openfeature-sdk", "~> 0.6.5"
end
