# frozen_string_literal: true

RSpec.describe Kettle::Jem::Appraisals::ModularGemfileGenerator do
  let(:tmpdir) { File.join(Dir.pwd, "tmp", "test_modular_gemfiles") }
  let(:generator) { described_class.new(base_dir: tmpdir) }

  before { FileUtils.mkdir_p(tmpdir) }
  after { FileUtils.rm_rf(tmpdir) }

  describe "#generate" do
    it "creates a modular gemfile for a tier1 gem" do
      path = generator.generate(
        gem_name: "activerecord",
        version: "7.1",
        ruby_series: "r3",
        sub_deps: {"sqlite3" => "1.6.9"},
      )

      expect(path).to eq("gemfiles/modular/activerecord/r3/v7.1.gemfile")

      full_path = File.join(tmpdir, path)
      expect(File.exist?(full_path)).to be true

      content = File.read(full_path)
      expect(content).to include('gem "activerecord", "~> 7.1.0"')
      expect(content).to include('gem "sqlite3", "~> 1.6.9"')
    end

    it "creates the directory structure" do
      generator.generate(gem_name: "sequel", version: "5.0", ruby_series: "r3")
      expect(Dir.exist?(File.join(tmpdir, "gemfiles", "modular", "sequel", "r3"))).to be true
    end
  end

  describe "#generate_tier2" do
    it "creates a tier2 gemfile" do
      path = generator.generate_tier2(gem_name: "omniauth", version: "2.1", ruby_series: "r3")

      expect(path).to eq("gemfiles/modular/omniauth/r3/v2.1.gemfile")

      full_path = File.join(tmpdir, path)
      content = File.read(full_path)
      expect(content).to include('gem "omniauth", "~> 2.1.0"')
    end

    it "keeps exact patch requirements intact" do
      path = generator.generate_tier2(gem_name: "omniauth", version: "2.1.3", ruby_series: "r3")

      content = File.read(File.join(tmpdir, path))
      expect(content).to include('gem "omniauth", "~> 2.1.3"')
    end
  end
end
