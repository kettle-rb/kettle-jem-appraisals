# frozen_string_literal: true

module Kettle
  module Jem
    module Appraisals
      # Derives Ruby series buckets from the min_ruby seams across gem versions.
      #
      # Instead of guessing which Ruby series are needed from the project gemspec,
      # this analyzes the actual min_ruby_version requirements of each selected
      # gem version to find "seams" — points where a gem drops Ruby support.
      #
      # Ruby series bucket semantics (counterintuitive!):
      #   r3     = catch-all for newest in that major (3.2+), NOT "3.0"
      #   r3.1   = covers 3.0–3.1 (older minors before the catch-all)
      #   r2     = catch-all for 2.7+ (last 2.x)
      #   r2.6   = covers 2.6 only
      #   r2.4   = covers 2.4–2.5
      #   vHEAD  = always included (git HEAD)
      #
      # The major-only bucket (rN) is always the NEWEST catch-all for that major.
      # Named rN.M buckets cover from that minor up to (but not including)
      # the next named bucket.
      class RubySeriesDetector
        attr_reader :resolver

        def initialize(resolver:)
          @resolver = resolver
        end

        # Detects Ruby series buckets needed for the given tier1 + tier2 gem configs.
        # Each gem config has "name" and "versions" keys.
        #
        # @param tier1_gems [Array<Hash>] tier1 gem configs with resolved versions
        # @param tier2_gems [Array<Hash>] tier2 gem configs with resolved versions
        # @param project_min_ruby [Gem::Version, nil] the project's own min_ruby (floor)
        # @return [Array<String>] sorted Ruby series bucket names, e.g. ["r3.1", "r3"]
        def detect(tier1_gems, tier2_gems, project_min_ruby: nil)
          result = detect_with_ranges(tier1_gems, tier2_gems, project_min_ruby: project_min_ruby)
          result[:buckets]
        end

        # Same as detect but also returns bucket ranges (floor/ceiling Gem::Versions).
        # @return [Hash] { buckets: [...], bucket_ranges: { "r2.4" => {floor:, ceiling:}, ... } }
        def detect_with_ranges(tier1_gems, tier2_gems, project_min_ruby: nil)
          all_min_rubies = collect_min_rubies(tier1_gems + tier2_gems)
          if all_min_rubies.empty?
            return {buckets: ["r3"], bucket_ranges: {"r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("99.99")}}}
          end

          if project_min_ruby
            floor = Gem::Version.new(project_min_ruby.to_s)
            all_min_rubies.reject! { |v| v < floor }
            all_min_rubies << floor unless all_min_rubies.include?(floor)
          end

          minor_versions = all_min_rubies.map { |v| minor_key(v) }.uniq.sort
          buckets_and_ranges = minor_versions_to_buckets_with_ranges(minor_versions)
          buckets = buckets_and_ranges[:buckets].sort_by { |b| bucket_sort_key(b) }
          {buckets: buckets, bucket_ranges: buckets_and_ranges[:ranges]}
        end

        # For a single gem, returns the seam points where min_ruby changes.
        # Returns an array of { version: "7.0", min_ruby: Gem::Version("2.7") } hashes,
        # one per seam (where the min_ruby requirement increased).
        #
        # @param gem_name [String]
        # @param versions [Array<String>] sorted minor version strings
        # @return [Array<Hash>] seam entries
        def find_seams(gem_name, versions)
          return [] if versions.empty?

          seams = []
          prev_ruby = nil

          versions.each do |ver|
            patch = latest_patch(gem_name, ver)
            min_ruby = resolver.min_ruby_version(gem_name, patch)
            next unless min_ruby

            if prev_ruby.nil? || min_ruby > prev_ruby
              seams << {version: ver, min_ruby: min_ruby}
            end
            prev_ruby = min_ruby
          end

          seams
        end

        private

        # Collects all distinct min_ruby versions across all gem versions.
        def collect_min_rubies(gem_configs)
          rubies = Set.new

          gem_configs.each do |config|
            name = config["name"]
            versions = config["versions"] || []
            next if versions.empty?

            seams = find_seams(name, versions)
            seams.each { |s| rubies << s[:min_ruby] }
          end

          rubies.to_a.sort
        end

        # Extracts the minor version key from a Gem::Version.
        # e.g., Gem::Version.new("3.1.4") → "3.1"
        def minor_key(version)
          segs = version.segments
          "#{segs[0]}.#{segs[1] || 0}"
        end

        # Converts a sorted list of minor version strings into bucket names
        # and computes the floor/ceiling Ruby version for each bucket.
        #
        # Algorithm: Group by major. Within each major, the LAST (newest) minor
        # becomes the catch-all "rN" bucket. Every earlier minor gets an
        # explicit "rN.M" bucket.
        #
        # Example: ["2.4", "2.6", "2.7", "3.0", "3.1", "3.2"]
        #   Major 2: 2.4→r2.4 (floor=2.4, ceil=2.5), 2.6→r2.6 (floor=2.6, ceil=2.6),
        #            2.7→r2 (floor=2.7, ceil=2.99)
        #   Major 3: 3.0/3.1→r3.1 (floor=3.0, ceil=3.1), 3.2→r3 (floor=3.2, ceil=3.99)
        def minor_versions_to_buckets_with_ranges(minor_versions)
          by_major = {}
          minor_versions.each do |mv|
            major = mv.split(".").first.to_i
            by_major[major] ||= []
            by_major[major] << mv
          end

          buckets = []
          ranges = {}

          by_major.each do |major, minors|
            sorted = minors.sort_by { |m| Gem::Version.new(m) }

            if sorted.size == 1
              bucket = "r#{major}"
              buckets << bucket
              ranges[bucket] = {
                floor: Gem::Version.new(sorted[0]),
                ceiling: Gem::Version.new("#{major}.99"),
              }
            else
              sorted.each_with_index do |mv, idx|
                minor_num = mv.split(".").last.to_i

                if idx == sorted.size - 1
                  # Last → catch-all
                  bucket = "r#{major}"
                  buckets << bucket
                  ranges[bucket] = {
                    floor: Gem::Version.new(mv),
                    ceiling: Gem::Version.new("#{major}.99"),
                  }
                else
                  # Named bucket rN.M where M = next_minor - 1
                  next_minor = sorted[idx + 1].split(".").last.to_i
                  upper = next_minor > 0 ? next_minor - 1 : minor_num
                  upper = [upper, minor_num].max
                  bucket = "r#{major}.#{upper}"
                  buckets << bucket unless buckets.include?(bucket)
                  # Don't overwrite if bucket already exists (merged ranges)
                  unless ranges.key?(bucket)
                    ranges[bucket] = {
                      floor: Gem::Version.new(mv),
                      ceiling: Gem::Version.new("#{major}.#{upper}"),
                    }
                  end
                end
              end
            end
          end

          {buckets: buckets.uniq, ranges: ranges}
        end

        # Sort key for bucket names so r2.4 < r2.6 < r2 < r3.1 < r3
        def bucket_sort_key(bucket)
          match = bucket.match(/\Ar(\d+)(?:\.(\d+))?\z/)
          return [99, 99] unless match

          major = match[1].to_i
          # Major-only buckets sort after all rN.M buckets of the same major
          minor = match[2] ? match[2].to_i : 999
          [major, minor]
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
