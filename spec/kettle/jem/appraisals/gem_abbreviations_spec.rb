# frozen_string_literal: true

RSpec.describe Kettle::Jem::Appraisals::GemAbbreviations do
  describe ".abbreviate" do
    it "returns known abbreviation for activerecord" do
      expect(described_class.abbreviate("activerecord")).to eq("ar")
    end

    it "returns known abbreviation for omniauth" do
      expect(described_class.abbreviate("omniauth")).to eq("oa")
    end

    it "returns known abbreviation for mongoid" do
      expect(described_class.abbreviate("mongoid")).to eq("mo")
    end

    it "returns known abbreviation for sequel" do
      expect(described_class.abbreviate("sequel")).to eq("sq")
    end

    it "returns the gem name itself for unknown gems" do
      expect(described_class.abbreviate("some-obscure-gem")).to eq("some-obscure-gem")
    end
  end

  describe ".format_version" do
    it "replaces dots with hyphens" do
      expect(described_class.format_version("7.1")).to eq("7-1")
    end

    it "handles single-segment versions" do
      expect(described_class.format_version("8")).to eq("8")
    end

    it "handles three-segment versions" do
      expect(described_class.format_version("7.1.5")).to eq("7-1-5")
    end
  end

  describe ".appraisal_name" do
    it "builds a full appraisal name with kja prefix" do
      result = described_class.appraisal_name("activerecord", "7.1", "omniauth", "2.1", "r3")
      expect(result).to eq("kja-ar-7-1-oa-2-1-r3")
    end

    it "uses full name for unknown gems" do
      result = described_class.appraisal_name("my-adapter", "1.0", "omniauth", "2.0", "r3")
      expect(result).to eq("kja-my-adapter-1-0-oa-2-0-r3")
    end

    it "builds a tier1-only name when tier2 is nil" do
      result = described_class.appraisal_name("mail", "2.8", nil, nil, "r3")
      expect(result).to eq("kja-mail-2-8-r3")
    end
  end
end
