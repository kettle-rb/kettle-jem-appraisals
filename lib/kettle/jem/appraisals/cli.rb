# frozen_string_literal: true

require "yaml"
require "fileutils"
require "set"

module Kettle
  module Jem
    module Appraisals
      # CLI entry point for kettle-jem-appraisals.
      #
      # Auto-detects mode (+scaffold+ vs +resolve+) based on config state,
      # or accepts explicit +--scaffold+ / +--resolve+ flags.
      #
      # In *scaffold* mode, reads the project gemspec, excludes standard-library
      # gems, and writes a skeleton +.kettle-jem.yml+ with tier1 candidates.
      #
      # In *resolve* mode, queries RubyGems for version data, assigns gem
      # versions to Ruby-series buckets, generates modular gemfiles, an
      # +Appraisals+ file, and workflow strategy matrix snippets.
      #
      # @example Run from the command line
      #   Kettle::Jem::Appraisals::CLI.run(["--resolve"])
      #
      # @example Instantiate and run
      #   cli = Kettle::Jem::Appraisals::CLI.new(["--scaffold"], project_dir: "/path/to/gem")
      #   cli.run
      class CLI
        # @return [String] name of the per-project YAML configuration file
        CONFIG_FILE = ".kettle-jem.yml"

        # @return [String] top-level key in the YAML config that holds the appraisal matrix
        APPRAISAL_MATRIX_KEY = "appraisal_matrix"

        # @return [Integer] default freshness TTL in seconds (7 days)
        DEFAULT_FRESHNESS_TTL = 604_800 # 7 days in seconds

        # @return [Array<String>] command-line arguments
        # @return [String] absolute path to the project directory
        attr_reader :args, :project_dir

        # @param args [Array<String>] command-line arguments (e.g., +["--scaffold"]+, +["--resolve"]+, +["--force"]+)
        # @param project_dir [String] path to the project root (defaults to the current working directory)
        def initialize(args = [], project_dir: Dir.pwd)
          @args = args
          @project_dir = project_dir
        end

        class << self
          # Convenience entry point: instantiates a CLI and runs it.
          #
          # @param args [Array<String>] command-line arguments
          # @return [void]
          def run(args)
            new(args).run
          end
        end

        # Detects the appropriate mode and dispatches to scaffold or resolve.
        #
        # @return [void]
        def run
          mode = detect_mode
          case mode
          when :scaffold
            run_scaffold
          when :resolve
            run_resolve
          else
            $stderr.puts "Unknown mode: #{mode}"
            exit(1)
          end
        end

        private

        def detect_mode
          return :scaffold if args.include?("--scaffold")
          return :resolve if args.include?("--resolve")

          config = load_config
          matrix = config[APPRAISAL_MATRIX_KEY]

          # Auto-detect: if no versions are present, scaffold mode
          if matrix.nil? || !has_versions?(matrix)
            :scaffold
          else
            :resolve
          end
        end

        def has_versions?(matrix)
          gems = matrix["gems"] || {}
          %w[tier1 tier2].any? { |tier|
            (gems[tier] || []).any? { |g| g["versions"] && !g["versions"].empty? }
          }
        end

        # ── Scaffold Mode ────────────────────────────────────────────────

        def run_scaffold
          puts "🍲 kettle-jem-appraisals: scaffold mode"
          gemspec_path = find_gemspec
          unless gemspec_path
            $stderr.puts "  ❌ No gemspec found in #{project_dir}"
            exit(1)
          end

          puts "  📦 Reading gemspec: #{File.basename(gemspec_path)}"
          runtime_deps = extract_runtime_deps(gemspec_path)
          exclusions = XStdLibsExclusion.from_template

          filtered = runtime_deps.reject { |name| exclusions.include?(name) }
          puts "  🔍 Found #{runtime_deps.size} runtime deps, #{runtime_deps.size - filtered.size} excluded"
          puts "  📋 Candidates: #{filtered.join(", ")}" unless filtered.empty?

          config = load_config
          matrix = config[APPRAISAL_MATRIX_KEY] || {}
          matrix["mode"] ||= "semver"
          matrix["freshness_ttl"] ||= DEFAULT_FRESHNESS_TTL
          matrix["gems"] ||= {}
          matrix["gems"]["tier1"] = filtered.map { |name| {"name" => name} }
          matrix["gems"]["tier2"] ||= []

          config[APPRAISAL_MATRIX_KEY] = matrix
          write_config(config)

          puts "  ✅ Wrote scaffold to #{CONFIG_FILE}"
          puts ""
          puts "  Next steps:"
          puts "  1. Edit #{CONFIG_FILE} — arrange gems into tier1 and tier2"
          puts "  2. Run `kettle-jem-appraisals` again (or `--resolve`) to generate matrix"
        end

        # ── Resolve Mode ─────────────────────────────────────────────────

        def run_resolve
          puts "🍲 kettle-jem-appraisals: resolve mode"

          config = load_config
          matrix = config[APPRAISAL_MATRIX_KEY]
          unless matrix
            $stderr.puts "  ❌ No #{APPRAISAL_MATRIX_KEY} in #{CONFIG_FILE}. Run --scaffold first."
            exit(1)
          end

          # Check freshness TTL
          if !args.include?("--force") && fresh?(matrix)
            puts "  ⏩ Matrix is still fresh (resolved #{time_ago(matrix["resolved_at"])} ago). Use --force to re-resolve."
            return
          end

          global_mode = matrix["mode"] || "semver"
          gems_config = matrix["gems"] || {}
          tier1_gems = gems_config["tier1"] || []
          tier2_gems = gems_config["tier2"] || []

          if tier1_gems.empty?
            $stderr.puts "  ❌ No tier1 gems configured. Run --scaffold first."
            exit(1)
          end

          resolver = GemVersionResolver.new
          builder = MatrixBuilder.new(resolver: resolver)
          sub_resolver = SubDepResolver.new(resolver: resolver)
          gemfile_gen = ModularGemfileGenerator.new(base_dir: project_dir)

          # Resolve tier1 versions
          tier1_gems.each do |gem_config|
            name = gem_config["name"]
            mode = gem_config["mode"] || gems_config.dig("tier1_mode") || global_mode
            requirements = gem_requirements(gem_config)
            include_versions = gem_include_versions(gem_config)
            exclude_versions = gem_exclude_versions(gem_config)
            puts "  🔄 Resolving #{name} (mode: #{mode})..."
            selected_versions = builder.select_versions(name, mode: mode, requirements: requirements)
            gem_config["versions"] = finalize_versions(selected_versions, include_versions, exclude_versions)
            puts "    → #{gem_config["versions"].size} versions: #{gem_config["versions"].join(", ")}"
          end

          # Resolve tier2 versions
          tier2_gems.each do |gem_config|
            name = gem_config["name"]
            mode = gem_config["mode"] || gems_config.dig("tier2_mode") || global_mode
            requirements = gem_requirements(gem_config)
            include_versions = gem_include_versions(gem_config)
            exclude_versions = gem_exclude_versions(gem_config)
            puts "  🔄 Resolving #{name} (mode: #{mode})..."
            selected_versions = builder.select_versions(name, mode: mode, requirements: requirements)
            gem_config["versions"] = finalize_versions(selected_versions, include_versions, exclude_versions)
            puts "    → #{gem_config["versions"].size} versions: #{gem_config["versions"].join(", ")}"
          end

          # Resolve sub-deps for tier1 gems
          tier1_gems.each do |gem_config|
            name = gem_config["name"]
            # Use the latest version to determine sub-deps
            latest = gem_config["versions"]&.last
            next unless latest

            deps = sub_resolver.resolve(name, latest)
            gem_config["deps"] = deps.keys unless deps.empty?
            puts "    📦 #{name} sub-deps: #{deps.keys.join(", ")}" unless deps.empty?
          end

          # Detect Ruby series from ALL version seams (not just selected versions).
          # The full seam set determines the bucket landscape — modes only affect
          # which versions we TEST, not which Ruby ranges exist.
          series_detector = RubySeriesDetector.new(resolver: resolver)
          project_min_ruby = detect_project_min_ruby

          # Build full-version gem configs for seam detection
          all_versions_by_gem = {}
          all_version_configs = (tier1_gems + tier2_gems).map do |gc|
            tier_mode =
              if tier1_gems.include?(gc)
                gems_config.dig("tier1_mode") || global_mode
              else
                gems_config.dig("tier2_mode") || global_mode
              end
            mode = gc["mode"] || tier_mode
            requirements = gem_requirements(gc)
            include_versions = gem_include_versions(gc)
            exclude_versions = gem_exclude_versions(gc)
            all_versions = all_versions_for(
              resolver,
              gc["name"],
              mode: mode,
              requirements: requirements,
              include_versions: include_versions,
              exclude_versions: exclude_versions,
            )
            all_versions_by_gem[gc["name"]] = all_versions
            {"name" => gc["name"], "versions" => all_versions}
          end
          detection = series_detector.detect_with_ranges(all_version_configs, [], project_min_ruby: project_min_ruby)
          ruby_series = detection[:buckets]
          bucket_ranges = detection[:bucket_ranges]
          puts "  🔴 Ruby series: #{ruby_series.join(", ")}"

          # Compute seams from ALL versions (for assignment) and show analysis
          all_seams = {}
          (tier1_gems + tier2_gems).each do |gem_config|
            all_versions = all_versions_by_gem[gem_config["name"]] || []
            seams = series_detector.find_seams(gem_config["name"], all_versions)
            all_seams[gem_config["name"]] = seams
            next if seams.empty?

            seam_str = seams.map { |s| "#{s[:version]}→ruby≥#{s[:min_ruby]}" }.join(", ")
            puts "    🔗 #{gem_config["name"]} seams: #{seam_str}"
          end

          appraisal_entries = build_matrix(
            tier1_gems,
            tier2_gems,
            ruby_series,
            bucket_ranges,
            all_seams,
            all_versions_by_gem,
            resolver,
            builder,
            gemfile_gen,
            sub_resolver,
          )

          puts "  📊 Generated #{appraisal_entries.size} appraisal entries"

          # Generate workflow strategy matrix snippets
          workflow_gen = WorkflowStrategyGenerator.new(
            bucket_ranges: bucket_ranges,
            exec_cmd: matrix.dig("exec_cmd") || "rake spec",
          )
          workflow_groups = workflow_gen.generate(appraisal_entries)
          workflow_groups.each do |lifecycle, entries|
            puts "    🔧 #{lifecycle}.yml: #{entries.size} matrix entries"
          end

          # Clean up stale kja-* flat gemfiles from previous runs
          cleanup_stale_gemfiles(appraisal_entries)

          # Write Appraisals file
          appraisals_content = AppraisalsGenerator.generate(appraisal_entries)
          appraisals_path = File.join(project_dir, "Appraisals")
          File.write(appraisals_path, appraisals_content)
          puts "  📝 Wrote #{appraisals_path}"

          # Update config with resolved_at timestamp
          matrix["resolved_at"] = Time.now.to_i
          config[APPRAISAL_MATRIX_KEY] = matrix
          write_config(config)

          # Run bin/appraisal generate
          if File.exist?(File.join(project_dir, "bin", "appraisal"))
            puts "  🔧 Running bin/appraisal generate..."
            system("bin/appraisal", "generate", chdir: project_dir)
          else
            puts "  ⚠️  bin/appraisal not found — run `bundle binstubs appraisal2` then `bin/appraisal generate`"
          end

          puts "  ✅ Resolve complete"
        end

        # ── Helpers ──────────────────────────────────────────────────────

        # Removes stale kja-* flat gemfiles from gemfiles/ that are no longer
        # in the current matrix. Only touches files matching the PREFIX pattern.
        def cleanup_stale_gemfiles(current_entries)
          prefix = GemAbbreviations::PREFIX
          gemfiles_dir = File.join(project_dir, "gemfiles")
          return unless File.directory?(gemfiles_dir)

          current_names = current_entries.map { |e| e[:name] }.to_set
          stale = Dir.glob(File.join(gemfiles_dir, "#{prefix}-*.gemfile")).reject { |f|
            basename = File.basename(f, ".gemfile")
            current_names.include?(basename)
          }

          return if stale.empty?

          stale.each { |f| FileUtils.rm_f(f) }
          puts "  🗑️  Removed #{stale.size} stale gemfile(s)"
        end

        def load_config
          path = File.join(project_dir, CONFIG_FILE)
          return {} unless File.exist?(path)

          YAML.safe_load_file(path, permitted_classes: [Symbol]) || {}
        end

        def write_config(config)
          path = File.join(project_dir, CONFIG_FILE)
          File.write(path, YAML.dump(config))
        end

        def find_gemspec
          pattern = File.join(project_dir, "*.gemspec")
          Dir.glob(pattern).first
        end

        def extract_runtime_deps(gemspec_path)
          # Use kettle-dev's gemspec reader if available, otherwise parse manually
          content = File.read(gemspec_path)
          deps = []
          content.each_line do |line|
            stripped = line.lstrip
            next if stripped.start_with?("#")

            if (match = stripped.match(/add_(?:runtime_)?dependency\s*\(?\s*["']([^"']+)["']/))
              deps << match[1]
            end
          end
          deps.uniq
        end

        def fresh?(matrix)
          resolved_at = matrix["resolved_at"]
          return false unless resolved_at

          ttl = matrix["freshness_ttl"] || DEFAULT_FRESHNESS_TTL
          (Time.now.to_i - resolved_at) < ttl
        end

        def time_ago(timestamp)
          return "unknown" unless timestamp

          seconds = Time.now.to_i - timestamp
          if seconds < 3600
            "#{seconds / 60}m"
          elsif seconds < 86_400
            "#{seconds / 3600}h"
          else
            "#{seconds / 86_400}d"
          end
        end

        # Extracts the project's min_ruby from its gemspec (used as a floor).
        def detect_project_min_ruby
          gemspec_path = find_gemspec
          return unless gemspec_path

          content = File.read(gemspec_path)
          if (match = content.match(/required_ruby_version.*?>=.*?(\d+\.\d+)/))
            Gem::Version.new(match[1])
          end
        end

        # Builds the matrix using optimal bucket assignments.
        # Instead of cross-producting all versions × all buckets, each tier1
        # version is assigned to its optimal bucket (the newest Ruby where
        # that version is the best choice).
        #
        # Tier2 versions are all compatible versions for each tier1's bucket.
        def build_matrix(tier1_gems, tier2_gems, ruby_series, bucket_ranges, all_seams, all_versions_by_gem, resolver, builder, gemfile_gen, sub_resolver)
          entries = []

          tier1_gems.each do |t1|
            t1_name = t1["name"]
            t1_versions = t1["versions"] || []
            t1_seams = all_seams[t1_name] || []

            # Assign each tier1 version to its optimal bucket
            t1_assignments = builder.assign_version_buckets(
              t1_name,
              t1_versions,
              seams: t1_seams,
              buckets: ruby_series,
              bucket_ranges: bucket_ranges,
              all_versions: all_versions_by_gem[t1_name],
            )

            if t1_assignments.empty?
              puts "    ⚠️  No bucket assignments for #{t1_name}, falling back to latest bucket"
              t1_assignments = t1_versions.map { |v| {version: v, bucket: ruby_series.last} }
            end

            # Show assignments
            t1_assignments.each do |a|
              label = a[:filler] ? " (filler)" : ""
              puts "    📌 #{t1_name} #{a[:version]} → #{a[:bucket]}#{label}"
            end

            if tier2_gems.empty?
              # Tier1-only entries (no tier2 cross)
              t1_assignments.each do |t1_a|
                t1_ver = t1_a[:version]
                rs = t1_a[:bucket]
                ruby_min = bucket_ranges.dig(rs, :floor)
                sub_deps = sub_resolver.resolve(t1_name, t1_ver, ruby_min: ruby_min)

                t1_gemfile = gemfile_gen.generate(
                  gem_name: t1_name,
                  version: t1_ver,
                  ruby_series: rs,
                  sub_deps: sub_deps,
                )

                x_std_libs_gemfile = "gemfiles/modular/x_std_libs/#{rs}/libs.gemfile"

                entries << {
                  name: GemAbbreviations.appraisal_name(t1_name, t1_ver, nil, nil, rs),
                  tier1_gemfile: t1_gemfile,
                  tier2_gemfile: nil,
                  x_std_libs_gemfile: x_std_libs_gemfile,
                  ruby_series: rs,
                }
              end
            else
              tier2_gems.each do |t2|
                t2_name = t2["name"]
                t2_versions = t2["versions"] || []

                t1_assignments.each do |t1_a|
                  t1_ver = t1_a[:version]
                  rs = t1_a[:bucket]

                  # Find compatible tier2 versions for this bucket
                  compatible_t2 = t2_versions.select { |t2_ver|
                    compatible?(t2_name, t2_ver, rs, bucket_ranges, resolver)
                  }

                  # If no compatible tier2 versions, skip
                  next if compatible_t2.empty?

                  compatible_t2.each do |t2_ver|
                    ruby_min = bucket_ranges.dig(rs, :floor)
                    sub_deps = sub_resolver.resolve(t1_name, t1_ver, ruby_min: ruby_min)

                    t1_gemfile = gemfile_gen.generate(
                      gem_name: t1_name,
                      version: t1_ver,
                      ruby_series: rs,
                      sub_deps: sub_deps,
                    )
                    t2_gemfile = gemfile_gen.generate_tier2(
                      gem_name: t2_name, version: t2_ver, ruby_series: rs,
                    )

                    x_std_libs_gemfile = "gemfiles/modular/x_std_libs/#{rs}/libs.gemfile"

                    entries << {
                      name: GemAbbreviations.appraisal_name(t1_name, t1_ver, t2_name, t2_ver, rs),
                      tier1_gemfile: t1_gemfile,
                      tier2_gemfile: t2_gemfile,
                      x_std_libs_gemfile: x_std_libs_gemfile,
                      ruby_series: rs,
                    }
                  end
                end
              end
            end
          end

          entries
        end

        # Checks if a tier2 gem version is compatible with a Ruby series bucket.
        def compatible?(gem_name, gem_ver, ruby_series, bucket_ranges, resolver)
          range = bucket_ranges[ruby_series]
          return true unless range

          gem_ruby = resolver.min_ruby_version(gem_name, latest_minor_patch(gem_name, gem_ver, resolver))
          # If gem requires a Ruby newer than the bucket's ceiling, incompatible
          return false if gem_ruby && gem_ruby > range[:ceiling]

          true
        rescue StandardError
          true
        end

        def latest_minor_patch(gem_name, minor_version, resolver)
          all = resolver.versions(gem_name)
          prefix = "#{minor_version}."
          matching = all.select { |v| v[:number].start_with?(prefix) || v[:number] == minor_version }
          return minor_version if matching.empty?

          matching.max_by { |v| Gem::Version.new(v[:number]) }[:number]
        end

        def gem_requirements(gem_config)
          values = [gem_config["requirements"]]
            .flatten
            .compact
            .flat_map { |value| value.is_a?(Array) ? value : [value] }
            .map(&:to_s)
            .map(&:strip)
            .reject(&:empty?)
          return if values.empty?

          values
        end

        def gem_include_versions(gem_config)
          values = [gem_config["include_versions"]]
            .flatten
            .compact
            .flat_map { |value| value.is_a?(Array) ? value : [value] }
            .map(&:to_s)
            .map(&:strip)
            .reject(&:empty?)
          return if values.empty?

          sort_versions(values)
        end

        def gem_exclude_versions(gem_config)
          values = [gem_config["exclude_versions"]]
            .flatten
            .compact
            .flat_map { |value| value.is_a?(Array) ? value : [value] }
            .map(&:to_s)
            .map(&:strip)
            .reject(&:empty?)
          return if values.empty?

          sort_versions(values)
        end

        def all_versions_for(resolver, gem_name, mode:, requirements: nil, include_versions: nil, exclude_versions: nil)
          base = if mode == "patch"
            resolver.versions(gem_name, requirements: requirements).map { |entry| entry[:number] }
          else
            resolver.minor_versions_by_major(gem_name, requirements: requirements).flat_map { |entry| entry[:minors] }
          end

          finalize_versions(base, include_versions, exclude_versions)
        end

        def merge_versions(base_versions, include_versions)
          sort_versions(Array(base_versions) + Array(include_versions))
        end

        def finalize_versions(base_versions, include_versions, exclude_versions)
          merged = merge_versions(base_versions, include_versions)
          subtract_versions(merged, exclude_versions)
        end

        def subtract_versions(base_versions, exclude_versions)
          excluded = Array(exclude_versions).to_set
          return sort_versions(base_versions) if excluded.empty?

          sort_versions(Array(base_versions).reject { |version| excluded.include?(version) })
        end

        def sort_versions(values)
          values.compact.uniq.sort_by { |version| Gem::Version.new(version) }
        end
      end
    end
  end
end
