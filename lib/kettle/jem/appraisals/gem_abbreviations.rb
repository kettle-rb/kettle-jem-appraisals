# frozen_string_literal: true

module Kettle
  module Jem
    module Appraisals
      # Registry of common gem name abbreviations for appraisal naming.
      # Format: `{tier1-abbrev}-{t1-version}-{tier2-abbrev}-{t2-version}-{ruby-series}`
      # Example: `ar-7-1-oa-2-1-r3`
      module GemAbbreviations
        ABBREVIATIONS = {
          "activerecord" => "ar",
          "actionmailer" => "am",
          "actionpack" => "ap",
          "activesupport" => "as",
          "activejob" => "aj",
          "actioncable" => "ac",
          "actionview" => "av",
          "activestorage" => "ast",
          "actionmailbox" => "amb",
          "actiontext" => "at",
          "omniauth" => "oa",
          "mongoid" => "mo",
          "sequel" => "sq",
          "couch_potato" => "cp",
          "rom" => "rom",
          "rom-sql" => "rsql",
        }.freeze

        # Returns the abbreviation for a gem name, or the gem name itself
        # (with hyphens preserved) if no abbreviation is registered.
        def self.abbreviate(gem_name)
          ABBREVIATIONS.fetch(gem_name, gem_name)
        end

        # Formats a version string for use in appraisal names.
        # Replaces dots with hyphens: "7.1" -> "7-1"
        def self.format_version(version)
          version.to_s.tr(".", "-")
        end

        # Builds a full appraisal name from tier1, tier2, and ruby series components.
        # Example: appraisal_name("activerecord", "7.1", "omniauth", "2.1", "r3")
        #   => "ar-7-1-oa-2-1-r3"
        def self.appraisal_name(tier1_gem, tier1_version, tier2_gem, tier2_version, ruby_series)
          parts = [
            abbreviate(tier1_gem),
            format_version(tier1_version),
          ]
          if tier2_gem
            parts << abbreviate(tier2_gem)
            parts << format_version(tier2_version)
          end
          parts << ruby_series
          parts.join("-")
        end
      end
    end
  end
end
