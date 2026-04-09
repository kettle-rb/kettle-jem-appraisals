# frozen_string_literal: true

module Kettle
  module Jem
    module Appraisals
      # Generates GitHub Actions workflow strategy matrix entries from the
      # resolved appraisal matrix.
      #
      # Groups entries by workflow lifecycle category (+current+, +supported+,
      # +legacy+, +unsupported+, +ancient+) based on Ruby bucket ranges.
      #
      # Each matrix entry maps to a single CI job: a specific appraisal
      # (tier1×tier2 version combo) on a specific Ruby version.
      #
      # == Lifecycle categories (kettle-jem convention)
      #
      #   current     — latest stable MRI ("ruby"), plus jruby/truffleruby
      #   supported   — maintained MRI versions (currently 3.2, 3.3, 3.4)
      #   legacy      — security-only MRI (3.0, 3.1)
      #   unsupported — EOL but recent MRI (2.6, 2.7)
      #   ancient     — very old MRI (2.3, 2.4, 2.5)
      #
      # @example
      #   gen = WorkflowStrategyGenerator.new(bucket_ranges: ranges, exec_cmd: "rake spec")
      #   groups = gen.generate(appraisal_entries)
      #   #=> { "current" => [{ruby: "ruby", appraisal: "kja-ar-8-r3", ...}], ... }
      class WorkflowStrategyGenerator
        # @return [Hash{String => Hash}] Ruby lifecycle boundaries mapping lifecycle
        #   name to min/max +Gem::Version+ ranges (update as Ruby EOL progresses)
        LIFECYCLE_RANGES = {
          "current" => {ruby_alias: "ruby", min: Gem::Version.new("3.4"), max: Gem::Version.new("3.99")},
          "supported" => {min: Gem::Version.new("3.2"), max: Gem::Version.new("3.3")},
          "legacy" => {min: Gem::Version.new("3.0"), max: Gem::Version.new("3.1")},
          "unsupported" => {min: Gem::Version.new("2.6"), max: Gem::Version.new("2.7")},
          "ancient" => {min: Gem::Version.new("2.3"), max: Gem::Version.new("2.5")},
        }.freeze

        # @return [Hash{String => Hash}] bucket → +{floor: Gem::Version, ceiling: Gem::Version}+
        attr_reader :bucket_ranges

        # @return [String] the shell command to execute in each CI matrix job
        attr_reader :exec_cmd

        # @param bucket_ranges [Hash{String => Hash}] bucket → +{floor: Gem::Version, ceiling: Gem::Version}+
        # @param exec_cmd [String] the test/build command (default: +"rake spec"+)
        def initialize(bucket_ranges:, exec_cmd: "rake spec")
          @bucket_ranges = bucket_ranges
          @exec_cmd = exec_cmd
        end

        # Groups appraisal entries into workflow lifecycle files with matrix entries.
        #
        # @param appraisal_entries [Array<Hash>] entries from {CLI} build_matrix, each with
        #   +:name+, +:ruby_series+, and gemfile path keys
        # @return [Hash{String => Array<Hash>}] lifecycle name → sorted array of matrix
        #   include entries, each with +:ruby+, +:appraisal+, +:exec_cmd+, +:gemfile+,
        #   +:rubygems+, and +:bundler+ keys
        def generate(appraisal_entries)
          grouped = Hash.new { |h, k| h[k] = [] }

          appraisal_entries.each do |entry|
            bucket = entry[:ruby_series]
            range = bucket_ranges[bucket]
            next unless range

            lifecycle = lifecycle_for(range[:floor])
            ruby_version = ruby_version_for(range[:floor], lifecycle)

            grouped[lifecycle] << build_matrix_entry(entry, ruby_version)
          end

          # Sort entries within each lifecycle by appraisal name
          grouped.transform_values { |entries| entries.sort_by { |e| e[:appraisal] } }
        end

        # Generates YAML-compatible +strategy.matrix.include+ snippets for each lifecycle.
        #
        # @param appraisal_entries [Array<Hash>] entries from {CLI} build_matrix
        # @return [Hash{String => String}] lifecycle name → YAML strategy matrix snippet
        def generate_yaml_snippets(appraisal_entries)
          groups = generate(appraisal_entries)

          groups.transform_values { |entries|
            lines = ["strategy:", "  matrix:", "    include:"]
            entries.each do |entry|
              lines << "      - ruby: #{entry[:ruby].inspect}"
              lines << "        appraisal: #{entry[:appraisal].inspect}"
              lines << "        exec_cmd: #{entry[:exec_cmd].inspect}"
              lines << "        gemfile: #{entry[:gemfile].inspect}"
              lines << "        rubygems: #{entry[:rubygems].inspect}"
              lines << "        bundler: #{entry[:bundler].inspect}"
            end
            lines.join("\n")
          }
        end

        private

        # Determines which lifecycle a Ruby floor version belongs to.
        def lifecycle_for(ruby_floor)
          LIFECYCLE_RANGES.each do |name, range|
            return name if ruby_floor >= range[:min] && ruby_floor <= range[:max]
          end
          # Fallback: if below all ranges, ancient; if above, current
          return "ancient" if ruby_floor < LIFECYCLE_RANGES["ancient"][:min]
          "current"
        end

        # Maps a Ruby floor version to the setup-ruby version string.
        # For "current", uses "ruby" alias (latest stable).
        # For all others, uses the explicit minor version (e.g., "3.2").
        def ruby_version_for(ruby_floor, lifecycle)
          if lifecycle == "current"
            "ruby"
          else
            segs = ruby_floor.segments
            "#{segs[0]}.#{segs[1] || 0}"
          end
        end

        def build_matrix_entry(entry, ruby_version)
          {
            ruby: ruby_version,
            appraisal: entry[:name],
            exec_cmd: exec_cmd,
            gemfile: "Appraisal.root",
            rubygems: "latest",
            bundler: "latest",
          }
        end
      end
    end
  end
end
