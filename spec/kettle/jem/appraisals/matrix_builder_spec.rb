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
        allow(resolver).to receive(:versions).and_return(
          by_major.flat_map { |m| m[:minors].map { |v| {number: "#{v}.0"} } },
        )
        allow(resolver).to receive(:min_ruby_version).and_return(nil)
      end

      it "returns last minor of older majors + all of current" do
        result = builder.select_versions("test-gem", mode: "semver")
        # major 5: last=5.2 (no ruby cutoffs with nil)
        # major 6: last=6.1
        # major 7: all
        expect(result).to include("5.2", "6.1", "7.0", "7.1", "7.2")
      end
    end

    it "raises on invalid mode" do
      expect { builder.select_versions("test-gem", mode: "invalid") }
        .to raise_error(ArgumentError, /Invalid mode/)
    end
  end
end
