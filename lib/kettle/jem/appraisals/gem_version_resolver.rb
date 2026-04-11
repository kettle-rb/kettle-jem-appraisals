# frozen_string_literal: true

module Kettle
  module Jem
    module Appraisals
      # Queries the RubyGems.org API to resolve gem version information.
      #
      # Caches results per session to avoid redundant API calls.
      # Uses the v1 API for version listings and the v2 API for
      # per-version dependency data.
      #
      # Floor-detection logic (+min_ruby_version+, +parse_min_ruby+, and the
      # underlying HTTP calls) is delegated to
      # {Kettle::Jem::GemRubyFloor::Resolver} so the same implementation is
      # shared with the +kettle-jem+ gemspec harmonization pipeline.
      #
      # @example Fetch all stable versions of a gem
      #   resolver = GemVersionResolver.new
      #   resolver.versions("activerecord")
      #   #=> [{number: "7.1.3", ruby_version: ">= 2.7.0", ...}, ...]
      class GemVersionResolver
        # @return [String] base URL for the RubyGems v1 REST API (kept for
        #   compatibility; actual requests go through the floor resolver)
        RUBYGEMS_API_BASE = "https://rubygems.org/api/v1"

        # @return [Kettle::Jem::GemRubyFloor::Resolver] the shared floor resolver
        #   that owns the HTTP cache and all API calls
        attr_reader :floor_resolver

        # @return [Hash] in-memory cache of API responses (shared with the floor
        #   resolver — this is the same object, not a copy)
        def cache
          floor_resolver.cache
        end

        # @param floor_resolver [Kettle::Jem::GemRubyFloor::Resolver, nil]
        #   optional pre-built resolver (useful for sharing a warm cache across
        #   multiple components in the same session); a new instance is created
        #   when not provided
        def initialize(floor_resolver: nil)
          @floor_resolver = floor_resolver || Kettle::Jem::GemRubyFloor::Resolver.new
        end

        # Returns all versions of a gem, sorted oldest-to-newest.
        #
        # Each entry is a Hash with the keys +:number+, +:ruby_version+,
        # +:created_at+, and +:prerelease+.
        #
        # @param gem_name [String] the RubyGems gem name
        # @param include_prerelease [Boolean] when +true+, includes pre-release versions (default: +false+)
        # @return [Array<Hash>] version hashes sorted by +Gem::Version+
        def versions(gem_name, include_prerelease: false, requirements: nil)
          raw = fetch_versions(gem_name)
          versions = raw.map { |v|
            {
              number: v["number"],
              ruby_version: v["ruby_version"],
              created_at: v["created_at"],
              prerelease: v["prerelease"],
            }
          }
          versions = versions.reject { |v| v[:prerelease] } unless include_prerelease
          requirement = normalize_requirements(requirements)
          if requirement
            versions = versions.select { |v| requirement.satisfied_by?(Gem::Version.new(v[:number])) }
          end
          versions.sort_by { |v| Gem::Version.new(v[:number]) }
        end

        # Returns version info (dependencies, ruby_version) for a specific gem version.
        #
        # Uses the v2 API which includes the full dependency structure.
        #
        # @param gem_name [String] the RubyGems gem name
        # @param version [String] an exact version string (e.g., +"7.1.3"+)
        # @return [Hash, nil] a Hash with +:number+, +:ruby_version+, and +:runtime_dependencies+,
        #   or +nil+ if the version was not found
        def version_info(gem_name, version)
          data = fetch_gem_info(gem_name, version)
          return unless data

          deps = data["dependencies"] || {}
          runtime_deps = (deps["runtime"] || []).map { |d|
            {name: d["name"], requirements: d["requirements"]}
          }

          {
            number: data["number"],
            ruby_version: data["ruby_version"],
            runtime_dependencies: runtime_deps,
          }
        end

        # Returns the minimum Ruby version required by a specific gem version.
        #
        # Delegates to {Kettle::Jem::GemRubyFloor::Resolver#min_ruby_version}.
        #
        # @param gem_name [String] the RubyGems gem name
        # @param version [String] an exact version string (e.g., +"7.1.3"+)
        # @return [Gem::Version, nil] the minimum required Ruby version, or +nil+ if unspecified
        def min_ruby_version(gem_name, version)
          floor_resolver.min_ruby_version(gem_name, version)
        end

        # Returns all minor versions (+X.Y+) for a gem, grouped by major version.
        #
        # @param gem_name [String] the RubyGems gem name
        # @return [Array<Hash>] sorted entries, each with +:major+ (Integer) and +:minors+ (Array<String>)
        # @example
        #   resolver.minor_versions_by_major("activerecord")
        #   #=> [{major: 6, minors: ["6.0", "6.1"]}, {major: 7, minors: ["7.0", "7.1", "7.2"]}]
        def minor_versions_by_major(gem_name, requirements: nil)
          vers = versions(gem_name, requirements: requirements)
          grouped = {}
          vers.each do |v|
            gv = Gem::Version.new(v[:number])
            segments = gv.segments
            major = segments[0]
            minor_str = "#{segments[0]}.#{segments[1]}"
            grouped[major] ||= Set.new
            grouped[major] << minor_str
          end
          grouped.sort_by(&:first).map { |major, minors|
            {major: major, minors: minors.sort_by { |m| Gem::Version.new(m) }.to_a}
          }
        end

        private

        # Delegates raw version list fetching to the floor resolver so the HTTP
        # cache is shared across both +GemVersionResolver+ and
        # +Kettle::Jem::GemRubyFloor::Resolver+ when they are used together.
        def fetch_versions(gem_name)
          floor_resolver.fetch_versions(gem_name)
        end

        # @return [String] base URL for the RubyGems v2 REST API
        RUBYGEMS_V2_API_BASE = "https://rubygems.org/api/v2/rubygems"

        # Delegates v2 gem info fetching to the floor resolver.
        def fetch_gem_info(gem_name, version)
          floor_resolver.fetch_gem_info(gem_name, version)
        end

        # Delegates requirement string parsing to the floor resolver.
        def parse_min_ruby(requirement_str)
          floor_resolver.parse_min_ruby(requirement_str)
        end

        def normalize_requirements(requirements)
          return if requirements.nil?

          values = Array(requirements).flatten.compact.map(&:to_s).map(&:strip).reject(&:empty?)
          return if values.empty?

          Gem::Requirement.new(values)
        end
      end
    end
  end
end
