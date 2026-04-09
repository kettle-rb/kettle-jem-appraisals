# frozen_string_literal: true

module Kettle
  module Jem
    module Appraisals
      # @return [String] the gem version, following SemVer 2.0.0
      module Version
        VERSION = "0.1.0"
      end
      # @return [String] convenience alias for the version constant
      VERSION = Version::VERSION # Traditional Constant Location
    end
  end
end
