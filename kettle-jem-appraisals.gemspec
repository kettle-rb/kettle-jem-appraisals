# coding: utf-8
# frozen_string_literal: true

# kettle-jem:freeze
# To retain chunks of comments & code during kettle-jem templating:
# Wrap custom sections with freeze markers (e.g., as above and below this comment chunk).
# kettle-jem will then preserve content between those markers across template runs.
# kettle-jem:unfreeze

gem_version =
  if RUBY_VERSION >= "3.1" # rubocop:disable Gemspec/RubyVersionGlobalsUsage
    Module.new.tap { |mod| Kernel.load("#{__dir__}/lib/kettle/jem/appraisals/version.rb", mod) }::Kettle::Jem::Appraisals::Version::VERSION
  else
    lib = File.expand_path("lib", __dir__)
    $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
    require "kettle/jem/appraisals/version"
    Kettle::Jem::Appraisals::Version::VERSION
  end

Gem::Specification.new do |spec|
  spec.name = "kettle-jem-appraisals"
  spec.version = gem_version
  spec.authors = ["Peter H. Boling"]
  spec.email = ["floss@galtzo.com"]

  spec.summary = "🍲 Auto-generate Appraisal matrices for kettle-jem managed gems"
  spec.description = "🍲 Kettle::Jem::Appraisals auto-generates CI test matrices from RubyGems API data. Scaffolds tier1/tier2 gem lists from gemspec, resolves version spreads per mode (major/minor/minor-minmax/semver), generates modular gemfiles and Appraisals files. Part of the kettle-rb ecosystem."
  spec.homepage = "https://github.com/kettle-rb/kettle-jem-appraisals"
  spec.licenses = ["AGPL-3.0-only"]
  spec.required_ruby_version = ">= 3.1.0"

  unless ENV.include?("SKIP_GEM_SIGNING")
    user_cert = "certs/#{ENV.fetch("GEM_CERT_USER", ENV["USER"])}.pem"
    cert_file_path = File.join(__dir__, user_cert)
    cert_chain = cert_file_path.split(",")
    cert_chain.select! { |fp| File.exist?(fp) }
    if cert_file_path && cert_chain.any?
      spec.cert_chain = cert_chain
      if $PROGRAM_NAME.end_with?("gem") && ARGV[0] == "build"
        spec.signing_key = File.join(Gem.user_home, ".ssh", "gem-private_key.pem")
      end
    end
  end

  spec.metadata["homepage_uri"] = "https://kettle-jem-appraisals.galtzo.com/"
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/v#{spec.version}"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/v#{spec.version}/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["documentation_uri"] = "https://www.rubydoc.info/gems/#{spec.name}/#{spec.version}"
  spec.metadata["funding_uri"] = "https://github.com/sponsors/pboling"
  spec.metadata["wiki_uri"] = "#{spec.homepage}/wiki"
  spec.metadata["news_uri"] = "https://www.railsbling.com/tags/#{spec.name}"
  spec.metadata["discord_uri"] = "https://discord.gg/3qme4XHNKN"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "lib/**/*.rb",
    "sig/**/*.rbs",
  ]

  spec.extra_rdoc_files = Dir[
    "CHANGELOG.md",
    "CITATION.cff",
    "CODE_OF_CONDUCT.md",
    "CONTRIBUTING.md",
    "FUNDING.md",
    "LICENSE.txt",
    "README.md",
    "SECURITY.md",
  ]
  spec.rdoc_options += [
    "--title",
    "#{spec.name} - #{spec.summary}",
    "--main",
    "README.md",
    "--exclude",
    "^sig/",
    "--line-numbers",
    "--inline-source",
    "--quiet",
  ]
  spec.require_paths = ["lib"]
  spec.bindir = "exe"
  spec.executables = ["kettle-jem-appraisals"]

  # Runtime dependencies
  spec.add_dependency("kettle-dev", ">= 2.0")
  spec.add_dependency("kettle-jem", ">= 1.0")
  spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.9")

  # kettle-jem:freeze
  # Dev dependencies
  spec.add_development_dependency("bundler-audit", "~> 0.9.3")
  spec.add_development_dependency("rake", "~> 13.0")
  spec.add_development_dependency("rspec", "~> 3.13")
  spec.add_development_dependency("kettle-test", "~> 1.0", ">= 1.0.10")
  # kettle-jem:unfreeze
end
