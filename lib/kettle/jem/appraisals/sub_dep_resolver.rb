# frozen_string_literal: true

module Kettle
  module Jem
    module Appraisals
      # Resolves sub-dependency versions for a tier1 gem version within a Ruby series.
      # For each sub-dep, finds the newest version satisfying:
      #   (tier1's gemspec dep requirement) ∩ (Ruby-series compatibility)
      #
      # "Newest version where the following version drops support for a Ruby
      #  version that the current version supports" — i.e., the last version
      #  compatible with the target Ruby series.
      class SubDepResolver
        attr_reader :resolver

        def initialize(resolver:)
          @resolver = resolver
        end

        # Resolves sub-deps for a given tier1 gem at a specific version.
        # Returns a hash: { "sqlite3" => "1.6.9", ... }
        #
        # @param gem_name [String] tier1 gem name
        # @param version [String] tier1 gem version (e.g., "7.1")
        # @param ruby_min [Gem::Version, nil] minimum Ruby for the target series
        # @return [Hash<String, String>] sub-dep name => resolved version
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
