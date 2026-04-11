# frozen_string_literal: true

RSpec.describe Kettle::Jem::Appraisals::GemVersionResolver do
  let(:floor_resolver) { instance_double(Kettle::Jem::GemRubyFloor::Resolver) }
  let(:resolver) { described_class.new(floor_resolver: floor_resolver) }
  let(:raw_versions) do
    [
      {"number" => "6.0.0", "ruby_version" => ">= 2.5.0", "created_at" => "2020-01-01T00:00:00.000Z", "prerelease" => false},
      {"number" => "6.1.0", "ruby_version" => ">= 2.5.0", "created_at" => "2020-02-01T00:00:00.000Z", "prerelease" => false},
      {"number" => "6.1.1", "ruby_version" => ">= 2.5.0", "created_at" => "2020-03-01T00:00:00.000Z", "prerelease" => false},
      {"number" => "7.0.0", "ruby_version" => ">= 2.7.0", "created_at" => "2021-01-01T00:00:00.000Z", "prerelease" => false},
      {"number" => "7.1.0.beta1", "ruby_version" => ">= 2.7.0", "created_at" => "2021-02-01T00:00:00.000Z", "prerelease" => true},
    ]
  end

  before do
    allow(floor_resolver).to receive(:fetch_versions).with("rails").and_return(raw_versions)
  end

  describe "#versions" do
    it "filters stable versions by requirements" do
      result = resolver.versions("rails", requirements: [">= 6.1", "< 7.0"])

      expect(result.map { |entry| entry[:number] }).to eq(%w[6.1.0 6.1.1])
    end
  end

  describe "#minor_versions_by_major" do
    it "groups only matching versions by major and minor" do
      result = resolver.minor_versions_by_major("rails", requirements: [">= 6.1", "< 7.0"])

      expect(result).to eq([{major: 6, minors: %w[6.1]}])
    end
  end
end
