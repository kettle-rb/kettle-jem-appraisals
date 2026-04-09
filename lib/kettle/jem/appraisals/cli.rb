# frozen_string_literal: true

require "yaml"
require "fileutils"

module Kettle
  module Jem
    module Appraisals
      # CLI entry point for kettle-jem-appraisals.
      # Auto-detects mode (scaffold vs resolve) based on config state,
      # or accepts explicit --scaffold / --resolve flags.
      class CLI
        CONFIG_FILE = ".kettle-jem.yml"
        APPRAISAL_MATRIX_KEY = "appraisal_matrix"
        DEFAULT_FRESHNESS_TTL = 604_800 # 7 days in seconds

        attr_reader :args, :project_dir

        def initialize(args = [], project_dir: Dir.pwd)
          @args = args
          @project_dir = project_dir
        end

        def self.run(args)
          new(args).run
        end

        def run
          mode = detect_mode
          case mode
          when :scaffold
            run_scaffold
          when :resolve
            run_resolve
          else
            $stderr.puts "Unknown mode: #{mode}"
            exit 1
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
            exit 1
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
            exit 1
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
            exit 1
          end

          resolver = GemVersionResolver.new
          builder = MatrixBuilder.new(resolver: resolver)
          sub_resolver = SubDepResolver.new(resolver: resolver)
          gemfile_gen = ModularGemfileGenerator.new(base_dir: project_dir)

          # Resolve tier1 versions
          tier1_gems.each do |gem_config|
            name = gem_config["name"]
            mode = gem_config["mode"] || gems_config.dig("tier1_mode") || global_mode
            puts "  🔄 Resolving #{name} (mode: #{mode})..."
            gem_config["versions"] = builder.select_versions(name, mode: mode)
            puts "    → #{gem_config["versions"].size} versions: #{gem_config["versions"].join(", ")}"
          end

          # Resolve tier2 versions
          tier2_gems.each do |gem_config|
            name = gem_config["name"]
            mode = gem_config["mode"] || gems_config.dig("tier2_mode") || global_mode
            puts "  🔄 Resolving #{name} (mode: #{mode})..."
            gem_config["versions"] = builder.select_versions(name, mode: mode)
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

          # Build the cross-product matrix
          ruby_series = detect_ruby_series
          appraisal_entries = build_matrix(tier1_gems, tier2_gems, ruby_series, resolver, gemfile_gen, sub_resolver)

          puts "  📊 Generated #{appraisal_entries.size} appraisal entries"

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

        # Detects which Ruby series buckets are relevant based on min_ruby from gemspec.
        def detect_ruby_series
          gemspec_path = find_gemspec
          return ["r3"] unless gemspec_path

          content = File.read(gemspec_path)
          if (match = content.match(/required_ruby_version.*?>=.*?(\d+\.\d+)/))
            min_ruby = Gem::Version.new(match[1])
            series = []
            # Generate buckets based on min_ruby
            major = min_ruby.segments[0]
            series << "r#{major}"
            # If the gem supports an older major, add that too
            series << "r#{major - 1}" if major > 2
            series
          else
            ["r3"]
          end
        end

        # Builds the full matrix: tier1 × tier2 × ruby_series
        def build_matrix(tier1_gems, tier2_gems, ruby_series, resolver, gemfile_gen, sub_resolver)
          entries = []

          tier1_gems.each do |t1|
            t1_name = t1["name"]
            t1_versions = t1["versions"] || []

            tier2_gems.each do |t2|
              t2_name = t2["name"]
              t2_versions = t2["versions"] || []

              t1_versions.each do |t1_ver|
                t2_versions.each do |t2_ver|
                  ruby_series.each do |rs|
                    # Check compatibility — skip if neither gem can run on this Ruby
                    next unless compatible?(t1_name, t1_ver, t2_name, t2_ver, rs, resolver)

                    # Resolve sub-deps for this combination
                    ruby_min = ruby_series_min_version(rs)
                    sub_deps = sub_resolver.resolve(t1_name, t1_ver, ruby_min: ruby_min)

                    # Generate modular gemfiles
                    t1_gemfile = gemfile_gen.generate(
                      gem_name: t1_name, version: t1_ver,
                      ruby_series: rs, sub_deps: sub_deps,
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

        # Checks if a tier1+tier2 combination is compatible with a Ruby series.
        def compatible?(t1_name, t1_ver, t2_name, t2_ver, ruby_series, resolver)
          rs_min = ruby_series_min_version(ruby_series)
          return true unless rs_min

          t1_ruby = resolver.min_ruby_version(t1_name, latest_minor_patch(t1_name, t1_ver, resolver))
          t2_ruby = resolver.min_ruby_version(t2_name, latest_minor_patch(t2_name, t2_ver, resolver))

          # If either gem requires a newer Ruby than the series provides, skip
          return false if t1_ruby && t1_ruby > rs_min
          return false if t2_ruby && t2_ruby > rs_min

          true
        rescue StandardError
          true # If we can't determine, include it
        end

        def latest_minor_patch(gem_name, minor_version, resolver)
          all = resolver.versions(gem_name)
          prefix = "#{minor_version}."
          matching = all.select { |v| v[:number].start_with?(prefix) || v[:number] == minor_version }
          return minor_version if matching.empty?

          matching.max_by { |v| Gem::Version.new(v[:number]) }[:number]
        end

        # Maps ruby series bucket names to minimum Ruby versions.
        def ruby_series_min_version(ruby_series)
          case ruby_series
          when "r2.4" then Gem::Version.new("2.4")
          when "r2.6" then Gem::Version.new("2.6")
          when "r2" then Gem::Version.new("2.7")
          when "r3.1" then Gem::Version.new("3.0")
          when "r3" then Gem::Version.new("3.2")
          when "r4" then Gem::Version.new("4.0")
          else
            match = ruby_series.match(/\Ar(\d+)(?:\.(\d+))?\z/)
            return nil unless match

            major = match[1].to_i
            minor = match[2]&.to_i
            Gem::Version.new(minor ? "#{major}.#{minor}" : "#{major}.0")
          end
        end
      end
    end
  end
end
