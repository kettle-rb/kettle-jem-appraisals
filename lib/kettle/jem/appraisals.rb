# frozen_string_literal: true

require "version_gem"
require_relative "appraisals/version"

Kettle::Jem::Appraisals::Version.class_eval do
  extend VersionGem::Basic
end

module Kettle
  module Jem
    module Appraisals
      autoload :CLI, "kettle/jem/appraisals/cli"
      autoload :GemAbbreviations, "kettle/jem/appraisals/gem_abbreviations"
      autoload :GemVersionResolver, "kettle/jem/appraisals/gem_version_resolver"
      autoload :MatrixBuilder, "kettle/jem/appraisals/matrix_builder"
      autoload :ModularGemfileGenerator, "kettle/jem/appraisals/modular_gemfile_generator"
      autoload :AppraisalsGenerator, "kettle/jem/appraisals/appraisals_generator"
      autoload :RubySeriesDetector, "kettle/jem/appraisals/ruby_series_detector"
      autoload :SubDepResolver, "kettle/jem/appraisals/sub_dep_resolver"
      autoload :XStdLibsExclusion, "kettle/jem/appraisals/x_std_libs_exclusion"
    end
  end
end
