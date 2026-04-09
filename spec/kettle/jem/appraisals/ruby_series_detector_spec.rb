# frozen_string_literal: true

RSpec.describe Kettle::Jem::Appraisals::RubySeriesDetector do
  let(:resolver) { instance_double(Kettle::Jem::Appraisals::GemVersionResolver) }
  let(:detector) { described_class.new(resolver: resolver) }

  describe "#find_seams" do
    before do
      # Mock versions list for latest_patch resolution
      allow(resolver).to receive(:versions).and_return(
        [
          {number: "5.2.8"}, {number: "6.0.6"}, {number: "6.1.7"},
          {number: "7.0.8"}, {number: "7.1.5"}, {number: "7.2.2"},
        ],
      )
    end

    it "identifies seams where min_ruby changes" do
      # AR 5.2 → Ruby 2.3, AR 6.0 → Ruby 2.5, AR 7.0 → Ruby 2.7, AR 7.2 → Ruby 3.1
      allow(resolver).to receive(:min_ruby_version).with("activerecord", "5.2.8").and_return(Gem::Version.new("2.3"))
      allow(resolver).to receive(:min_ruby_version).with("activerecord", "6.0.6").and_return(Gem::Version.new("2.5"))
      allow(resolver).to receive(:min_ruby_version).with("activerecord", "6.1.7").and_return(Gem::Version.new("2.5"))
      allow(resolver).to receive(:min_ruby_version).with("activerecord", "7.0.8").and_return(Gem::Version.new("2.7"))
      allow(resolver).to receive(:min_ruby_version).with("activerecord", "7.1.5").and_return(Gem::Version.new("2.7"))
      allow(resolver).to receive(:min_ruby_version).with("activerecord", "7.2.2").and_return(Gem::Version.new("3.1"))

      seams = detector.find_seams("activerecord", ["5.2", "6.0", "6.1", "7.0", "7.1", "7.2"])

      expect(seams.size).to eq(4)
      expect(seams[0]).to eq({version: "5.2", min_ruby: Gem::Version.new("2.3")})
      expect(seams[1]).to eq({version: "6.0", min_ruby: Gem::Version.new("2.5")})
      expect(seams[2]).to eq({version: "7.0", min_ruby: Gem::Version.new("2.7")})
      expect(seams[3]).to eq({version: "7.2", min_ruby: Gem::Version.new("3.1")})
    end

    it "returns empty for no versions" do
      expect(detector.find_seams("foo", [])).to eq([])
    end
  end

  describe "#detect" do
    before do
      allow(resolver).to receive(:versions).and_return(
        [{number: "1.0.0"}, {number: "2.0.0"}, {number: "2.1.0"}],
      )
    end

    context "with simple tier1 + tier2" do
      let(:tier1) { [{"name" => "mygem", "versions" => ["1.0", "2.0"]}] }
      let(:tier2) { [{"name" => "other", "versions" => ["2.1"]}] }

      it "returns r3 when all gems require >= 3.2" do
        allow(resolver).to receive(:min_ruby_version).and_return(Gem::Version.new("3.2"))

        result = detector.detect(tier1, tier2)
        expect(result).to eq(["r3"])
      end

      it "returns multiple buckets when seams span Ruby majors" do
        # mygem 1.0 → Ruby 2.7, mygem 2.0 → Ruby 3.1
        allow(resolver).to receive(:min_ruby_version).with("mygem", anything).and_return(Gem::Version.new("2.7"), Gem::Version.new("3.1"))
        allow(resolver).to receive(:min_ruby_version).with("other", anything).and_return(Gem::Version.new("3.1"))

        result = detector.detect(tier1, tier2)
        # Should have buckets for 2.7 and 3.1
        expect(result.size).to be >= 2
        # Should include a Ruby 2 bucket and a Ruby 3 bucket
        expect(result.any? { |b| b.start_with?("r2") }).to be true
        expect(result.any? { |b| b.start_with?("r3") }).to be true
      end
    end

    context "with project floor" do
      let(:tier1) { [{"name" => "mygem", "versions" => ["1.0", "2.0"]}] }
      let(:tier2) { [] }

      it "excludes buckets below project min_ruby" do
        # mygem 1.0 → Ruby 2.4, mygem 2.0 → Ruby 3.1
        allow(resolver).to receive(:min_ruby_version)
          .with("mygem", anything)
          .and_return(Gem::Version.new("2.4"), Gem::Version.new("3.1"))

        # Project requires >= 3.0, so Ruby 2.x buckets should be excluded
        result = detector.detect(tier1, tier2, project_min_ruby: Gem::Version.new("3.0"))
        expect(result.none? { |b| b.start_with?("r2") }).to be true
      end
    end

    context "with empty versions" do
      it "returns default r3" do
        result = detector.detect([], [])
        expect(result).to eq(["r3"])
      end
    end
  end
end
