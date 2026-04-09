# frozen_string_literal: true

module Kettle
  module Jem
    module Appraisals
      # Introspects the kettle-jem template's +x_std_libs/vHEAD.gemfile+ to determine
      # which gems are already handled by the standard library extraction framework.
      #
      # These gems should be excluded from appraisal matrix generation because they
      # are managed separately via the +x_std_libs+ modular gemfiles.
      #
      # @example Check if a gem is excluded
      #   XStdLibsExclusion.excluded?("mutex_m") #=> true
      #   XStdLibsExclusion.excluded?("sqlite3")  #=> false
      module XStdLibsExclusion
        # @return [Array<String>] gem names that are always excluded regardless of template content
        ALWAYS_EXCLUDED = %w[version_gem].freeze

        # Parses the x_std_libs vHEAD template to extract the set of gems
        # managed by the x_std_libs framework.
        #
        # The template contains +eval_gemfile+ lines like:
        #   eval_gemfile "../erb/vHEAD.gemfile"
        #   eval_gemfile "../mutex_m/vHEAD.gemfile"
        #
        # This extracts the gem directory names (+erb+, +mutex_m+, etc.)
        # and merges them with {ALWAYS_EXCLUDED}.
        #
        # @param template_path [String, nil] path to the vHEAD.gemfile template;
        #   when +nil+, uses {.default_template_path}
        # @return [Array<String>] frozen list of excluded gem names
        def self.from_template(template_path = nil)
          template_path ||= default_template_path
          return ALWAYS_EXCLUDED.dup unless template_path && File.exist?(template_path)

          gems = File.readlines(template_path).filter_map { |line|
            if (match = line.match(%r{eval_gemfile\s+["']\.\./([\w-]+)/}))
              match[1]
            end
          }

          (gems + ALWAYS_EXCLUDED).uniq.freeze
        end

        # Locates the +x_std_libs/vHEAD.gemfile+ in the installed kettle-jem gem.
        #
        # @return [String, nil] absolute path to the template file, or +nil+ if
        #   kettle-jem is not installed or the file does not exist
        def self.default_template_path
          spec = Gem::Specification.find_by_name("kettle-jem")
          path = File.join(spec.gem_dir, "template", "gemfiles", "modular", "x_std_libs", "vHEAD.gemfile.example")
          File.exist?(path) ? path : nil
        rescue Gem::MissingSpecError
          nil
        end

        # Returns whether the gem should be excluded from the appraisal matrix.
        #
        # @param gem_name [String] the gem name to check
        # @param exclusion_list [Array<String>, nil] an explicit exclusion list;
        #   when +nil+, calls {.from_template} to build the list
        # @return [Boolean] +true+ if the gem is excluded
        def self.excluded?(gem_name, exclusion_list: nil)
          (exclusion_list || from_template).include?(gem_name)
        end
      end
    end
  end
end
