# frozen_string_literal: true

module Kettle
  module Jem
    module Appraisals
      # Selects gem versions according to the configured mode.
      # Modes determine which versions from the full list to include in the matrix.
      class MatrixBuilder
        VALID_MODES = %w[major minor minor-minmax semver].freeze

        attr_reader :resolver

        def initialize(resolver:)
          @resolver = resolver
        end

        # Returns selected version strings for a gem according to the mode.
        # @param gem_name [String] the gem name
        # @param mode [String] one of VALID_MODES
        # @return [Array<String>] selected version strings like ["5.2", "6.0", "7.1"]
        def select_versions(gem_name, mode:)
          raise ArgumentError, "Invalid mode: #{mode}. Must be one of: #{VALID_MODES.join(", ")}" unless VALID_MODES.include?(mode)

          by_major = resolver.minor_versions_by_major(gem_name)
          return [] if by_major.empty?

          current_major = by_major.last[:major]

          case mode
          when "major"
            select_major(by_major)
          when "minor"
            select_minor(by_major)
          when "minor-minmax"
            select_minor_minmax(by_major, current_major)
          when "semver"
            select_semver(gem_name, by_major, current_major)
          end
        end

        private

        # One entry per major version (the latest minor of each).
        def select_major(by_major)
          by_major.map { |entry| entry[:minors].last }
        end

        # Every minor version across all supported majors.
        def select_minor(by_major)
          by_major.flat_map { |entry| entry[:minors] }
        end

        # First + last minor per major < current; all minors of current major.
        def select_minor_minmax(by_major, current_major)
          versions = []
          by_major.each do |entry|
            if entry[:major] < current_major
              minors = entry[:minors]
              versions << minors.first
              versions << minors.last if minors.size > 1
            else
              versions.concat(entry[:minors])
            end
          end
          versions.uniq
        end

        # Last minor per major < current + minors where required_ruby_version changes
        # (natural Ruby cutoff points) + all minors of current major.
        def select_semver(gem_name, by_major, current_major)
          versions = []

          by_major.each do |entry|
            if entry[:major] < current_major
              # Always include last minor of older majors
              versions << entry[:minors].last

              # Include minors where the next version drops Ruby support
              ruby_cutoff_versions = find_ruby_cutoff_versions(gem_name, entry[:minors])
              versions.concat(ruby_cutoff_versions)
            else
              # All minors of current major
              versions.concat(entry[:minors])
            end
          end

          versions.uniq.sort_by { |v| Gem::Version.new(v) }
        end

        # Finds versions where the following version drops support for a Ruby version
        # that the current version supports. These are natural cutoff points.
        # Returns the version *before* the drop (the last to support the Ruby version).
        def find_ruby_cutoff_versions(gem_name, minor_versions)
          return [] if minor_versions.size < 2

          cutoffs = []
          prev_ruby = nil

          minor_versions.each do |version|
            current_ruby = resolver.min_ruby_version(gem_name, latest_patch(gem_name, version))
            if prev_ruby && current_ruby && current_ruby > prev_ruby
              # This version requires a newer Ruby than the previous one.
              # The previous version is a cutoff point (last to support older Ruby).
              cutoffs << minor_versions[minor_versions.index(version) - 1]
            end
            prev_ruby = current_ruby
          end

          cutoffs
        end

        # Finds the latest patch release for a given minor version.
        # E.g., for "7.1" returns "7.1.5" (the highest 7.1.x).
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
