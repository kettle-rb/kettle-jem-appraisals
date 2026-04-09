# frozen_string_literal: true

RSpec.describe Kettle::Jem::Appraisals::WorkflowStrategyGenerator do
  let(:bucket_ranges) do
    {
      "r2.4" => {floor: Gem::Version.new("2.4"), ceiling: Gem::Version.new("2.4")},
      "r2.6" => {floor: Gem::Version.new("2.5"), ceiling: Gem::Version.new("2.6")},
      "r2" => {floor: Gem::Version.new("2.7"), ceiling: Gem::Version.new("2.99")},
      "r3.1" => {floor: Gem::Version.new("3.0"), ceiling: Gem::Version.new("3.1")},
      "r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")},
    }
  end

  let(:generator) do
    described_class.new(bucket_ranges: bucket_ranges, exec_cmd: "rake spec")
  end

  let(:appraisal_entries) do
    [
      {name: "ar-5-2-oa-1-r2.4", ruby_series: "r2.4", tier1_gemfile: "g1", tier2_gemfile: "g2", x_std_libs_gemfile: "g3"},
      {name: "ar-6-1-oa-1-r2.6", ruby_series: "r2.6", tier1_gemfile: "g1", tier2_gemfile: "g2", x_std_libs_gemfile: "g3"},
      {name: "ar-7-1-oa-2-r2", ruby_series: "r2", tier1_gemfile: "g1", tier2_gemfile: "g2", x_std_libs_gemfile: "g3"},
      {name: "ar-7-2-oa-2-r3.1", ruby_series: "r3.1", tier1_gemfile: "g1", tier2_gemfile: "g2", x_std_libs_gemfile: "g3"},
      {name: "ar-8-1-oa-2-r3", ruby_series: "r3", tier1_gemfile: "g1", tier2_gemfile: "g2", x_std_libs_gemfile: "g3"},
    ]
  end

  describe "#generate" do
    it "groups entries into lifecycle categories" do
      result = generator.generate(appraisal_entries)

      # r2.4(2.4)→ancient, r2.6(2.5)→ancient, r2(2.7)→unsupported, r3.1(3.0)→legacy, r3(3.2)→supported
      expect(result.keys).to contain_exactly("ancient", "unsupported", "legacy", "supported")
    end

    it "assigns ancient buckets (r2.4 → Ruby 2.4, r2.6 floor=2.5 → ancient)" do
      result = generator.generate(appraisal_entries)

      ancient = result["ancient"]
      # r2.4 (floor=2.4) and r2.6 (floor=2.5) both fall in ancient (2.3–2.5)
      expect(ancient.size).to eq(2)
      ruby_versions = ancient.map { |e| e[:ruby] }
      expect(ruby_versions).to include("2.4", "2.5")
    end

    it "assigns unsupported bucket (r2 floor=2.7) to unsupported" do
      result = generator.generate(appraisal_entries)

      unsupported = result["unsupported"]
      expect(unsupported.size).to eq(1)
      expect(unsupported.first[:ruby]).to eq("2.7")
    end

    it "assigns legacy bucket (r3.1 → Ruby 3.0) to legacy lifecycle" do
      result = generator.generate(appraisal_entries)

      legacy = result["legacy"]
      expect(legacy.size).to eq(1)
      expect(legacy.first[:ruby]).to eq("3.0")
    end

    it "assigns supported bucket (r3 floor=3.2) to supported lifecycle" do
      result = generator.generate(appraisal_entries)

      supported = result["supported"]
      expect(supported.size).to eq(1)
      expect(supported.first[:ruby]).to eq("3.2")
      expect(supported.first[:appraisal]).to eq("ar-8-1-oa-2-r3")
    end

    it "includes all required matrix entry fields" do
      result = generator.generate(appraisal_entries)

      result.each_value do |entries|
        entries.each do |entry|
          expect(entry).to include(:ruby, :appraisal, :exec_cmd, :gemfile, :rubygems, :bundler)
          expect(entry[:exec_cmd]).to eq("rake spec")
          expect(entry[:gemfile]).to eq("Appraisal.root")
        end
      end
    end

    it "sorts entries by appraisal name within each lifecycle" do
      result = generator.generate(appraisal_entries)

      result.each_value do |entries|
        names = entries.map { |e| e[:appraisal] }
        expect(names).to eq(names.sort)
      end
    end
  end

  describe "#generate_yaml_snippets" do
    it "returns YAML strategy strings per lifecycle" do
      snippets = generator.generate_yaml_snippets(appraisal_entries)

      expect(snippets).to be_a(Hash)
      snippets.each_value do |yaml|
        expect(yaml).to include("strategy:")
        expect(yaml).to include("matrix:")
        expect(yaml).to include("include:")
        expect(yaml).to include("ruby:")
        expect(yaml).to include("appraisal:")
      end
    end
  end

  describe "with only current-era buckets" do
    let(:bucket_ranges) do
      {"r3" => {floor: Gem::Version.new("3.4"), ceiling: Gem::Version.new("3.99")}}
    end

    let(:entries) do
      [{name: "foo-1-r3", ruby_series: "r3", tier1_gemfile: "g", tier2_gemfile: "g", x_std_libs_gemfile: "g"}]
    end

    it "groups everything under current with 'ruby' alias" do
      result = generator.generate(entries)
      expect(result.keys).to eq(["current"])
      expect(result["current"].first[:ruby]).to eq("ruby")
    end
  end

  describe "custom exec_cmd" do
    let(:generator) do
      described_class.new(bucket_ranges: bucket_ranges, exec_cmd: "rake spec:orm:active_record")
    end

    it "uses the custom exec_cmd in matrix entries" do
      result = generator.generate(appraisal_entries)

      result.each_value do |entries|
        entries.each do |entry|
          expect(entry[:exec_cmd]).to eq("rake spec:orm:active_record")
        end
      end
    end
  end
end
