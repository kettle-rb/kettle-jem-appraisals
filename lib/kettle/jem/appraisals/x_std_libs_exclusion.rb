# frozen_string_literal: true

module Kettle
  module Jem
    module Appraisals
      # Introspects the kettle-jem template's x_std_libs/vHEAD.gemfile to determine
      # which gems are already handled by the standard library extraction framework.
      # These gems should be excluded from appraisal matrix generation.
      module XStdLibsExclusion
        # Hard-coded exclusions that should never appear in a matrix.
        ALWAYS_EXCLUDED = %w[version_gem].freeze

        # Parses eval_gemfile lines from the x_std_libs vHEAD template to extract
        # the set of gems managed by the x_std_libs framework.
        #
        # The vHEAD.gemfile contains lines like:
        #   eval_gemfile "../erb/vHEAD.gemfile"
        #   eval_gemfile "../mutex_m/vHEAD.gemfile"
        #
        # This extracts the gem directory names (erb, mutex_m, etc.).
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

        # Locates the x_std_libs/vHEAD.gemfile in the installed kettle-jem gem.
        def self.default_template_path
          spec = Gem::Specification.find_by_name("kettle-jem")
          path = File.join(spec.gem_dir, "template", "gemfiles", "modular", "x_std_libs", "vHEAD.gemfile.example")
          File.exist?(path) ? path : nil
        rescue Gem::MissingSpecError
          nil
        end

        # Returns true if the gem should be excluded from the matrix.
        def self.excluded?(gem_name, exclusion_list: nil)
          (exclusion_list || from_template).include?(gem_name)
        end
      end
    end
  end
end
