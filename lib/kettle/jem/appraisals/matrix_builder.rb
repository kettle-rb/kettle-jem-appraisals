# frozen_string_literal: true

module Kettle
  module Jem
    module Appraisals
      # Selects gem versions according to the configured mode and assigns
      # each version to its optimal Ruby bucket.
      #
      # The optimal bucket for a gem version V is the NEWEST Ruby where V is
      # the best (latest) choice — i.e., the Ruby just below the next version's
      # min_ruby requirement. This is the inverted perspective: not "what's the
      # minimum Ruby this gem needs?" but "what's the newest Ruby where you'd
      # still use this gem version?"
      #
      # Example with activerecord:
      #   AR 5.2 (min_ruby=2.2) → optimal on r2.4 (Ruby 2.4 is newest before AR 6.0 needs 2.5)
      #   AR 6.1 (min_ruby=2.5) → optimal on r2.6 (Ruby 2.6 is newest before AR 7.0 needs 2.7)
      #   AR 7.1 (min_ruby=2.7) → optimal on r2   (Ruby 2.7 is newest before AR 7.2 needs 3.1)
      #   AR 7.2 (min_ruby=3.1) → optimal on r3.1 (Ruby 3.1 is newest before AR 8.0 needs 3.2)
      #   AR 8.1 (min_ruby=3.2) → optimal on r3   (catch-all, latest)
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

        # Assigns each selected version to its optimal Ruby bucket.
        #
        # Instead of cross-producting versions × all buckets, each version
        # maps to the ONE bucket where it is the best (newest) choice.
        #
        # Filler: if a bucket has no selected version assigned (gap from
        # mode selection skipping versions that naturally cover that bucket),
        # backfill with the newest version from a prior seam range that can
        # run on that bucket's Ruby.
        #
        # @param gem_name [String] gem name
        # @param selected_versions [Array<String>] versions selected by mode
        # @param seams [Array<Hash>] from RubySeriesDetector#find_seams
        # @param buckets [Array<String>] all detected Ruby bucket names
        # @param bucket_ranges [Hash<String, Hash>] bucket → {floor:, ceiling:} Gem::Versions
        # @return [Array<Hash>] [{version: "5.2", bucket: "r2.4"}, ...]
        def assign_version_buckets(gem_name, selected_versions, seams:, buckets:, bucket_ranges:)
          return [] if selected_versions.empty? || buckets.empty?

          # Build a lookup: version → min_ruby from seams
          # For versions between seams, inherit the previous seam's min_ruby
          all_minors = resolver.minor_versions_by_major(gem_name).flat_map { |e| e[:minors] }
          version_min_ruby = compute_version_min_rubies(all_minors, seams)

          # For each selected version, find which bucket it's optimal for.
          # "Optimal" = the bucket whose ceiling is just below the NEXT SEAM
          # boundary (from the full seam list, not just selected versions).
          # This correctly handles major mode where selected versions may skip seams.
          assignments = []
          selected_sorted = selected_versions.sort_by { |v| Gem::Version.new(v) }

          selected_sorted.each do |ver|
            ver_min_ruby = version_min_ruby[ver]
            next unless ver_min_ruby

            # Find the next seam boundary AFTER this version's min_ruby.
            # This is the min_ruby where a NEWER version of this gem takes over.
            # We use the full seam list, not just selected versions.
            next_seam_ruby = find_next_seam_ruby(ver, ver_min_ruby, all_minors, version_min_ruby)

            if next_seam_ruby
              bucket = find_bucket_below(next_seam_ruby, buckets, bucket_ranges)
            else
              # This is in the latest seam range — catch-all bucket
              bucket = buckets.last
            end

            assignments << {version: ver, bucket: bucket} if bucket
          end

          # Handle filler: fill gaps where buckets have no assigned version
          fill_bucket_gaps(assignments, selected_sorted, version_min_ruby, buckets, bucket_ranges, all_minors)
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
              versions << entry[:minors].last
              ruby_cutoff_versions = find_ruby_cutoff_versions(gem_name, entry[:minors])
              versions.concat(ruby_cutoff_versions)
            else
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
              cutoffs << minor_versions[minor_versions.index(version) - 1]
            end
            prev_ruby = current_ruby
          end

          cutoffs
        end

        # Finds the next seam's min_ruby AFTER a given version.
        # Walks the full version list to find where min_ruby next increases
        # after this version. Uses the full list (not selected), so mode
        # doesn't affect seam detection.
        def find_next_seam_ruby(ver, ver_min_ruby, all_minors, version_min_ruby)
          gem_ver = Gem::Version.new(ver)
          found_current = false

          all_minors.each do |mv|
            mv_gem = Gem::Version.new(mv)
            if mv_gem >= gem_ver
              found_current = true
            end
            next unless found_current

            mv_ruby = version_min_ruby[mv]
            next unless mv_ruby
            return mv_ruby if mv_ruby > ver_min_ruby
          end

          nil
        end

        # Builds a hash mapping each minor version string to its min_ruby (Gem::Version).
        # Versions between seams inherit the previous seam's min_ruby.
        # Values are clamped to MINIMUM_RUBY_FLOOR (setup-ruby GHA minimum).
        def compute_version_min_rubies(all_minors, seams)
          mapping = {}
          current_ruby = nil

          # Seams are sorted by version. Walk all minors and apply seam boundaries.
          seam_idx = 0
          all_minors.each do |ver|
            gem_ver = Gem::Version.new(ver)
            # Advance to the right seam
            while seam_idx < seams.size && Gem::Version.new(seams[seam_idx][:version]) <= gem_ver
              current_ruby = seams[seam_idx][:min_ruby]
              seam_idx += 1
            end
            if current_ruby
              mapping[ver] = [current_ruby, MINIMUM_RUBY_FLOOR].max
            end
          end

          mapping
        end

        # Finds the bucket whose range covers the Ruby version just below `ruby_floor`.
        # E.g., if ruby_floor is 2.5, returns the bucket for Ruby 2.4.
        def find_bucket_below(ruby_floor, buckets, bucket_ranges)
          # We want the bucket whose ceiling is just below ruby_floor
          best_bucket = nil
          best_ceiling = nil

          buckets.each do |b|
            range = bucket_ranges[b]
            next unless range
            ceiling = range[:ceiling]

            # The bucket's ceiling must be BELOW the next version's min_ruby
            next unless ceiling < ruby_floor

            if best_ceiling.nil? || ceiling > best_ceiling
              best_bucket = b
              best_ceiling = ceiling
            end
          end

          best_bucket
        end

        # Fills gaps where a bucket has no assigned version.
        # When mode selection (e.g., major) picks a version that skips a bucket
        # (e.g., AR 7.2 on r3.1 but nothing on r2), we backfill with the newest
        # unselected version from the gem's full version list that's optimal for
        # that bucket.
        def fill_bucket_gaps(assignments, selected_sorted, version_min_ruby, buckets, bucket_ranges, all_minors)
          covered = assignments.map { |a| a[:bucket] }.uniq

          # Build min_ruby for ALL minors (not just selected) for filler lookup
          uncovered = buckets - covered
          return assignments if uncovered.empty?

          uncovered.each do |bucket|
            range = bucket_ranges[bucket]
            next unless range

            # Find the newest minor version (from full list) whose min_ruby
            # falls within this bucket's range (floor <= min_ruby <= ceiling)
            filler = all_minors.reverse.find { |ver|
              ver_ruby = version_min_ruby[ver]
              next false unless ver_ruby

              ver_ruby >= range[:floor] && ver_ruby <= range[:ceiling]
            }

            # If no version has min_ruby IN the range, find the newest version
            # whose min_ruby is BELOW the range (it can still run on this Ruby)
            filler ||= all_minors.reverse.find { |ver|
              ver_ruby = version_min_ruby[ver]
              next false unless ver_ruby

              ver_ruby <= range[:ceiling]
            }

            assignments << {version: filler, bucket: bucket, filler: true} if filler
          end

          assignments.sort_by { |a| bucket_ranges.dig(a[:bucket], :floor) || Gem::Version.new("0") }
        end

        # Finds the latest patch release for a given minor version.
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
