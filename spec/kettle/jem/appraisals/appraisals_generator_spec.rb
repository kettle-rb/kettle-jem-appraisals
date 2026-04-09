# frozen_string_literal: true

RSpec.describe Kettle::Jem::Appraisals::AppraisalsGenerator do
  describe ".generate" do
    let(:matrix) do
      [
        {
          name: "kja-ar-7-1-oa-2-1-r3",
          tier1_gemfile: "gemfiles/modular/activerecord/r3/v7.1.gemfile",
          tier2_gemfile: "gemfiles/modular/omniauth/r3/v2.1.gemfile",
          x_std_libs_gemfile: "gemfiles/modular/x_std_libs/r3/libs.gemfile",
          ruby_series: "r3",
        },
        {
          name: "kja-sq-5-0-oa-2-1-r3",
          tier1_gemfile: "gemfiles/modular/sequel/r3/v5.0.gemfile",
          tier2_gemfile: "gemfiles/modular/omniauth/r3/v2.1.gemfile",
          x_std_libs_gemfile: "gemfiles/modular/x_std_libs/r3/libs.gemfile",
          ruby_series: "r3",
        },
      ]
    end

    it "generates valid Appraisals file content" do
      content = described_class.generate(matrix)
      expect(content).to include('appraise "kja-ar-7-1-oa-2-1-r3" do')
      expect(content).to include('eval_gemfile "gemfiles/modular/activerecord/r3/v7.1.gemfile"')
      expect(content).to include('eval_gemfile "gemfiles/modular/omniauth/r3/v2.1.gemfile"')
      expect(content).to include('eval_gemfile "gemfiles/modular/x_std_libs/r3/libs.gemfile"')
    end

    it "includes frozen_string_literal comment" do
      content = described_class.generate(matrix)
      expect(content).to start_with("# frozen_string_literal: true")
    end

    it "generates entries for all matrix items" do
      content = described_class.generate(matrix)
      expect(content).to include('appraise "kja-ar-7-1-oa-2-1-r3"')
      expect(content).to include('appraise "kja-sq-5-0-oa-2-1-r3"')
    end
  end
end
