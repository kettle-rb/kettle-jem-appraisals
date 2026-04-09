# frozen_string_literal: true

module Kettle
  module Jem
    module Appraisals
      # Registry of common gem name abbreviations for appraisal naming.
      #
      # All generated appraisal names are prefixed with {PREFIX} so that
      # regeneration can reliably identify and remove stale entries.
      #
      # Naming format: +kja-{tier1-abbrev}-{t1-version}-{tier2-abbrev}-{t2-version}-{ruby-series}+
      #
      # @example Abbreviated name
      #   GemAbbreviations.appraisal_name("activerecord", "7.1", "omniauth", "2.1", "r3")
      #   #=> "kja-ar-7-1-oa-2-1-r3"
      module GemAbbreviations
        # @return [String] prefix applied to every generated appraisal name,
        #   used to identify entries managed by kettle-jem-appraisals for cleanup
        PREFIX = "kja"

        # @return [Hash{String => String}] mapping of full gem names to short abbreviations
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

        # Returns the abbreviation for a gem name.
        #
        # Falls back to the full gem name (with hyphens preserved) when no
        # abbreviation is registered in {ABBREVIATIONS}.
        #
        # @param gem_name [String] the full RubyGems gem name
        # @return [String] abbreviated or original gem name
        # @example Known abbreviation
        #   GemAbbreviations.abbreviate("activerecord") #=> "ar"
        # @example Unknown gem (passthrough)
        #   GemAbbreviations.abbreviate("mail") #=> "mail"
        def self.abbreviate(gem_name)
          ABBREVIATIONS.fetch(gem_name, gem_name)
        end

        # Formats a version string for use in appraisal names.
        #
        # Replaces dots with hyphens so the name is safe for filenames and
        # shell identifiers.
        #
        # @param version [String] a version string (e.g., +"7.1"+)
        # @return [String] formatted version (e.g., +"7-1"+)
        # @example
        #   GemAbbreviations.format_version("7.1") #=> "7-1"
        def self.format_version(version)
          version.to_s.tr(".", "-")
        end

        # Builds a full appraisal name from tier1, tier2, and ruby series components.
        #
        # All names are prefixed with {PREFIX} for reliable cleanup on regeneration.
        # When +tier2_gem+ is +nil+, the tier2 segment is omitted.
        #
        # @param tier1_gem [String] tier1 gem name (e.g., +"activerecord"+)
        # @param tier1_version [String] tier1 gem version (e.g., +"7.1"+)
        # @param tier2_gem [String, nil] tier2 gem name, or +nil+ to omit
        # @param tier2_version [String, nil] tier2 gem version, or +nil+ to omit
        # @param ruby_series [String] ruby series bucket (e.g., +"r3"+)
        # @return [String] the full appraisal name
        # @example With tier2
        #   appraisal_name("activerecord", "7.1", "omniauth", "2.1", "r3")
        #   #=> "kja-ar-7-1-oa-2-1-r3"
        # @example Tier1 only
        #   appraisal_name("mail", "2.8", nil, nil, "r3")
        #   #=> "kja-mail-2-8-r3"
        def self.appraisal_name(tier1_gem, tier1_version, tier2_gem, tier2_version, ruby_series)
          parts = [
            PREFIX,
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
