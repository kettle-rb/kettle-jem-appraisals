# frozen_string_literal: true

RSpec.describe Kettle::Jem::Appraisals::MatrixBuilder do
  let(:resolver) { instance_double(Kettle::Jem::Appraisals::GemVersionResolver) }
  let(:builder) { described_class.new(resolver: resolver) }

  let(:by_major) do
    [
      {major: 5, minors: ["5.0", "5.1", "5.2"]},
      {major: 6, minors: ["6.0", "6.1"]},
      {major: 7, minors: ["7.0", "7.1", "7.2"]},
    ]
  end

  before do
    allow(resolver).to receive(:minor_versions_by_major).and_return(by_major)
  end

  describe "#select_versions" do
    context "with mode: major" do
      it "returns the latest minor of each major" do
        result = builder.select_versions("test-gem", mode: "major")
        expect(result).to eq(["5.2", "6.1", "7.2"])
      end
    end

    context "with mode: minor" do
      it "returns all minor versions" do
        result = builder.select_versions("test-gem", mode: "minor")
        expect(result).to eq(["5.0", "5.1", "5.2", "6.0", "6.1", "7.0", "7.1", "7.2"])
      end
    end

    context "with mode: patch" do
      before do
        allow(resolver).to receive(:versions)
          .with("test-gem", requirements: [">= 6.1", "< 7.0"])
          .and_return([{number: "6.1.0"}, {number: "6.1.1"}])
      end

      it "returns matching patch versions" do
        result = builder.select_versions("test-gem", mode: "patch", requirements: [">= 6.1", "< 7.0"])
        expect(result).to eq(["6.1.0", "6.1.1"])
      end
    end

    context "with mode: minor-minmax" do
      it "returns first+last for older majors, all for current" do
        result = builder.select_versions("test-gem", mode: "minor-minmax")
        # major 5 (< 7): first=5.0, last=5.2
        # major 6 (< 7): first=6.0, last=6.1
        # major 7 (current): all
        expect(result).to eq(["5.0", "5.2", "6.0", "6.1", "7.0", "7.1", "7.2"])
      end
    end

    context "with mode: semver" do
      before do
        # Mock the version resolver for semver mode
        allow(resolver).to receive_messages(
          versions: by_major.flat_map { |major| major[:minors].map { |version| {number: "#{version}.0"} } },
          min_ruby_version: nil,
        )
      end

      it "returns last minor of older majors + all of current" do
        result = builder.select_versions("test-gem", mode: "semver")
        # major 5: last=5.2 (no ruby cutoffs with nil)
        # major 6: last=6.1
        # major 7: all
        expect(result).to include("5.2", "6.1", "7.0", "7.1", "7.2")
      end
    end

    context "with mode: semver and a large current major (>9 minors)" do
      let(:large_minors) { (0..15).map { |i| "1.#{i}" } }
      let(:large_by_major) do
        [{major: 1, minors: large_minors}]
      end

      before do
        allow(resolver).to receive_messages(
          minor_versions_by_major: large_by_major,
          versions: large_minors.map { |version| {number: "#{version}.0"} },
        )
        # Simulate a Ruby cutoff at 1.8 (min_ruby jumps from 2.5 to 2.7)
        allow(resolver).to receive(:min_ruby_version) do |_gem, version|
          minor = version.split(".")[1].to_i
          if minor >= 8
            Gem::Version.new("2.7")
          else
            Gem::Version.new("2.5")
          end
        end
      end

      it "prunes to latest minor + Ruby-cutoff minors only" do
        result = builder.select_versions("big-gem", mode: "semver")
        # 1.7 is the last before 1.8 bumps min_ruby → Ruby cutoff
        # 1.15 is the latest minor
        expect(result).to contain_exactly("1.7", "1.15")
      end
    end

    it "raises on invalid mode" do
      expect { builder.select_versions("test-gem", mode: "invalid") }
        .to raise_error(ArgumentError, /Invalid mode/)
    end
  end

  describe "#assign_version_buckets" do
    # Simulate AR-like seams: 5.0→2.2, 6.0→2.5, 7.0→2.7, 7.2→3.1
    let(:seams) do
      [
        {version: "5.0", min_ruby: Gem::Version.new("2.2")},
        {version: "6.0", min_ruby: Gem::Version.new("2.5")},
        {version: "7.0", min_ruby: Gem::Version.new("2.7")},
        {version: "7.2", min_ruby: Gem::Version.new("3.1")},
      ]
    end

    let(:buckets) { ["r2.4", "r2.6", "r2", "r3.1", "r3"] }
    let(:bucket_ranges) do
      {
        "r2.4" => {floor: Gem::Version.new("2.4"), ceiling: Gem::Version.new("2.4")},
        "r2.6" => {floor: Gem::Version.new("2.5"), ceiling: Gem::Version.new("2.6")},
        "r2" => {floor: Gem::Version.new("2.7"), ceiling: Gem::Version.new("2.99")},
        "r3.1" => {floor: Gem::Version.new("3.0"), ceiling: Gem::Version.new("3.1")},
        "r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")},
      }
    end

    context "when in major mode (one per major)" do
      it "assigns each version to its optimal bucket and fills gaps" do
        selected = ["5.2", "6.1", "7.2"]
        result = builder.assign_version_buckets(
          "test-gem",
          selected,
          seams: seams,
          buckets: buckets,
          bucket_ranges: bucket_ranges,
        )

        version_buckets = result.map { |a| [a[:version], a[:bucket]] }

        # 5.2 → r2.4 (optimal: next seam at 6.0 needs 2.5, newest Ruby below is 2.4)
        expect(version_buckets).to include(["5.2", "r2.4"])

        # 6.1 → r2.6 (optimal: next seam at 7.0 needs 2.7, newest Ruby below is 2.6)
        expect(version_buckets).to include(["6.1", "r2.6"])

        # 7.2 → r3 (latest, catch-all since no higher seam in selected)
        # But actually 7.2 has seam 7.2→3.1 and no next seam → catch-all r3
        # Wait, 7.2 IS a seam itself. Let me check...
        # 7.2's min_ruby=3.1. No version after 7.2 in ALL minors has higher min_ruby
        # (since 7.2 is the last), so it gets catch-all.
        expect(version_buckets).to include(["7.2", "r3"])

        # r2 (Ruby 2.7) was uncovered → filler with 7.1 (newest version that can run on 2.7)
        filler_entries = result.select { |a| a[:filler] }
        expect(filler_entries.map { |a| a[:bucket] }).to include("r2")
      end
    end

    context "when in minor mode (all versions)" do
      it "assigns each version to its unique optimal bucket" do
        selected = ["5.0", "5.1", "5.2", "6.0", "6.1", "7.0", "7.1", "7.2"]
        result = builder.assign_version_buckets(
          "test-gem",
          selected,
          seams: seams,
          buckets: buckets,
          bucket_ranges: bucket_ranges,
        )

        # r2.4 should get a version from the 5.x range
        r24_versions = result.select { |a| a[:bucket] == "r2.4" }.map { |a| a[:version] }
        expect(r24_versions).not_to be_empty

        # r2.6 should get a version from the 6.x range
        r26_versions = result.select { |a| a[:bucket] == "r2.6" }.map { |a| a[:version] }
        expect(r26_versions).not_to be_empty

        # r2 should get a version from the 7.0-7.1 range
        r2_versions = result.select { |a| a[:bucket] == "r2" }.map { |a| a[:version] }
        expect(r2_versions).not_to be_empty
      end
    end

    context "with empty inputs" do
      it "returns empty for no selected versions" do
        result = builder.assign_version_buckets(
          "test-gem",
          [],
          seams: seams,
          buckets: buckets,
          bucket_ranges: bucket_ranges,
        )
        expect(result).to be_empty
      end

      it "returns empty for no buckets" do
        result = builder.assign_version_buckets(
          "test-gem",
          ["5.2"],
          seams: seams,
          buckets: [],
          bucket_ranges: {},
        )
        expect(result).to be_empty
      end
    end

    context "with patch versions and explicit all_versions" do
      let(:patch_seams) do
        [
          {version: "7.1.0", min_ruby: Gem::Version.new("3.0")},
          {version: "7.1.1", min_ruby: Gem::Version.new("3.2")},
        ]
      end

      it "assigns exact patch versions when patch mode is used" do
        result = builder.assign_version_buckets(
          "test-gem",
          ["7.1.0", "7.1.1"],
          seams: patch_seams,
          buckets: ["r3.1", "r3"],
          bucket_ranges: {
            "r3.1" => {floor: Gem::Version.new("3.0"), ceiling: Gem::Version.new("3.1")},
            "r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")},
          },
          all_versions: ["7.1.0", "7.1.1"],
        )

        expect(result.map { |entry| [entry[:version], entry[:bucket]] }).to include(["7.1.1", "r3"])
      end
    end
  end
end
