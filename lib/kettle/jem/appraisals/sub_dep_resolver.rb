# frozen_string_literal: true

module Kettle
  module Jem
    module Appraisals
      # Resolves sub-dependency versions for a tier1 gem version within a Ruby series.
      #
      # For each runtime dependency of the tier1 gem, finds the newest version
      # satisfying both the tier1 gem's gemspec constraint and the target Ruby
      # series compatibility.
      #
      # @example
      #   resolver = SubDepResolver.new(resolver: gem_version_resolver)
      #   resolver.resolve("activerecord", "7.1", ruby_min: Gem::Version.new("3.0"))
      #   #=> {"sqlite3" => "1.6.9"}
      class SubDepResolver
        # @return [GemVersionResolver] the resolver used to query RubyGems
        attr_reader :resolver

        # @param resolver [GemVersionResolver] a resolver instance for querying gem version data
        def initialize(resolver:)
          @resolver = resolver
        end

        # Resolves sub-dependencies for a given tier1 gem at a specific version.
        #
        # Queries the v2 API for the gem's runtime dependencies, excludes
        # standard-library gems (via {XStdLibsExclusion}), and resolves each
        # remaining dependency to a concrete version.
        #
        # @param gem_name [String] tier1 gem name (e.g., +"activerecord"+)
        # @param version [String] tier1 minor version string (e.g., +"7.1"+)
        # @param ruby_min [Gem::Version, nil] minimum Ruby version for the target series;
        #   when set, prefers the newest sub-dep version compatible with this Ruby
        # @return [Hash{String => String}] sub-dependency name → resolved version string
        def resolve(gem_name, version, ruby_min: nil)
          info = resolver.version_info(gem_name, latest_patch(gem_name, version))
          return {} unless info

          deps = {}
          info[:runtime_dependencies].each do |dep|
            dep_name = dep[:name]
            next if XStdLibsExclusion.excluded?(dep_name)

            resolved = resolve_single(dep_name, dep[:requirements], ruby_min: ruby_min)
            deps[dep_name] = resolved if resolved
          end
          deps
        end

        private

        # Finds the newest version of a sub-dep that satisfies both the
        # requirement constraint and the Ruby series compatibility.
        def resolve_single(dep_name, requirements_str, ruby_min: nil)
          all = resolver.versions(dep_name)
          return if all.empty?

          # Parse the requirement from the parent gem's dependency
          req = begin
            Gem::Requirement.new(requirements_str)
          rescue ArgumentError
            Gem::Requirement.default
          end

          # Filter to versions satisfying the requirement
          compatible = all.select { |v| req.satisfied_by?(Gem::Version.new(v[:number])) }
          return if compatible.empty?

          if ruby_min
            # Find the newest version compatible with the target Ruby
            # Walk backwards to find the latest version whose min_ruby <= ruby_min
            compatible.reverse_each do |v|
              v_ruby = resolver.min_ruby_version(dep_name, v[:number])
              next unless v_ruby.nil? || v_ruby <= ruby_min

              return v[:number]
            end
            # If nothing matches, return the oldest compatible version
            compatible.first[:number]
          else
            # No Ruby constraint — return newest compatible
            compatible.last[:number]
          end
        end

        def latest_patch(gem_name, minor_version)
          all_versions = resolver.versions(gem_name)
          prefix = "#{minor_version}."
          matching = all_versions.select { |v| v[:number].start_with?(prefix) || v[:number] == minor_version }
          return minor_version if matching.empty?

          matching.max_by { |v| Gem::Version.new(v[:number]) }[:number]
        end
      end
    end
  end
end
