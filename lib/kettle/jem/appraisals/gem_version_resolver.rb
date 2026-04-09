# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Kettle
  module Jem
    module Appraisals
      # Queries the RubyGems.org API to resolve gem version information.
      # Caches results per session to avoid redundant API calls.
      class GemVersionResolver
        RUBYGEMS_API_BASE = "https://rubygems.org/api/v1"

        attr_reader :cache

        def initialize
          @cache = {}
        end

        # Returns all versions of a gem as an array of hashes with keys:
        #   :number, :ruby_version, :created_at, :prerelease
        # Filters out prerelease versions by default.
        def versions(gem_name, include_prerelease: false)
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
          versions.sort_by { |v| Gem::Version.new(v[:number]) }
        end

        # Returns version info (dependencies, ruby_version) for a specific gem version.
        def version_info(gem_name, version)
          data = fetch_gem_info(gem_name, version)
          return nil unless data

          deps = (data["dependencies"] || {})
          runtime_deps = (deps["runtime"] || []).map { |d|
            {name: d["name"], requirements: d["requirements"]}
          }

          {
            number: data["version"],
            ruby_version: data["required_ruby_version"],
            runtime_dependencies: runtime_deps,
          }
        end

        # Returns the minimum Ruby version required by a specific gem version.
        # Returns nil if not specified.
        def min_ruby_version(gem_name, version)
          info = version_info(gem_name, version)
          return nil unless info && info[:ruby_version]

          parse_min_ruby(info[:ruby_version])
        end

        # Returns all minor versions (X.Y) for a gem, grouped by major.
        # Each entry: { major: N, minors: ["X.Y", ...] }
        def minor_versions_by_major(gem_name)
          vers = versions(gem_name)
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

        def fetch_versions(gem_name)
          cache_key = "versions:#{gem_name}"
          return @cache[cache_key] if @cache.key?(cache_key)

          uri = URI("#{RUBYGEMS_API_BASE}/versions/#{gem_name}.json")
          response = Net::HTTP.get_response(uri)
          raise "RubyGems API error for #{gem_name}: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

          @cache[cache_key] = JSON.parse(response.body)
        end

        def fetch_gem_info(gem_name, version)
          cache_key = "info:#{gem_name}:#{version}"
          return @cache[cache_key] if @cache.key?(cache_key)

          uri = URI("#{RUBYGEMS_API_BASE}/versions/#{gem_name}/#{version}.json")
          response = Net::HTTP.get_response(uri)
          return nil unless response.is_a?(Net::HTTPSuccess)

          @cache[cache_key] = JSON.parse(response.body)
        end

        # Extracts the minimum Ruby version from a requirement string like ">= 2.7.0"
        def parse_min_ruby(requirement_str)
          return nil if requirement_str.nil? || requirement_str.strip.empty?

          req = Gem::Requirement.new(requirement_str)
          # Find the >= constraint and extract its version
          req.requirements.each do |op, ver|
            return ver if op == ">="
          end
          # If only ~> is used, the base version is the minimum
          req.requirements.each do |op, ver|
            return ver if op == "~>"
          end
          nil
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
