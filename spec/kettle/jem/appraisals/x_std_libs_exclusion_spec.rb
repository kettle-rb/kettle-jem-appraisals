# frozen_string_literal: true

RSpec.describe Kettle::Jem::Appraisals::XStdLibsExclusion do
  describe ".from_template" do
    context "with a real template file" do
      it "includes version_gem in exclusions" do
        exclusions = described_class.from_template
        expect(exclusions).to include("version_gem")
      end
    end

    context "with a custom template path" do
      let(:tmpdir) { File.join(Dir.pwd, "tmp", "test_x_std_libs") }
      let(:template_path) { File.join(tmpdir, "vHEAD.gemfile") }

      before do
        FileUtils.mkdir_p(tmpdir)
        File.write(template_path, <<~GEMFILE)
          eval_gemfile "../erb/vHEAD.gemfile"
          eval_gemfile "../mutex_m/vHEAD.gemfile"
          eval_gemfile "../stringio/vHEAD.gemfile"
          eval_gemfile "../benchmark/vHEAD.gemfile"
        GEMFILE
      end

      after do
        FileUtils.rm_rf(tmpdir)
      end

      it "extracts gem names from eval_gemfile lines" do
        exclusions = described_class.from_template(template_path)
        expect(exclusions).to include("erb", "mutex_m", "stringio", "benchmark")
      end

      it "always includes version_gem" do
        exclusions = described_class.from_template(template_path)
        expect(exclusions).to include("version_gem")
      end
    end

    context "with nonexistent path" do
      it "returns ALWAYS_EXCLUDED" do
        exclusions = described_class.from_template("/nonexistent/path")
        expect(exclusions).to eq(["version_gem"])
      end
    end
  end

  describe ".excluded?" do
    it "returns true for version_gem" do
      expect(described_class.excluded?("version_gem")).to be true
    end

    it "returns false for arbitrary gem" do
      expect(described_class.excluded?("activerecord", exclusion_list: ["version_gem"])).to be false
    end
  end
end
