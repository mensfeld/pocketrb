# frozen_string_literal: true

RSpec.describe Pocketrb::CLI::Init do
  let(:workspace) { Dir.mktmpdir }
  let(:init_cmd) { described_class.new([], { workspace: workspace }) }

  after do
    FileUtils.rm_rf(workspace)
  end

  describe "#call" do
    it "creates .pocketrb directory" do
      init_cmd.call
      expect(Pathname.new(workspace).join(".pocketrb")).to be_directory
    end

    it "creates config.yml" do
      init_cmd.call
      config_file = Pathname.new(workspace).join(".pocketrb", "config.yml")
      expect(config_file).to exist
    end

    it "creates skills directory" do
      init_cmd.call
      expect(Pathname.new(workspace).join("skills")).to be_directory
    end

    it "creates TOOLS.md" do
      init_cmd.call
      tools_file = Pathname.new(workspace).join("TOOLS.md")
      expect(tools_file).to exist
      expect(File.read(tools_file)).to include("Built-in Tools")
    end

    it "does not overwrite existing TOOLS.md" do
      tools_file = Pathname.new(workspace).join("TOOLS.md")
      File.write(tools_file, "Custom content")

      init_cmd.call
      expect(File.read(tools_file)).to eq("Custom content")
    end

    it "warns if workspace is already initialized" do
      init_cmd.call
      expect { init_cmd.call }.to output(/already initialized/).to_stdout
    end
  end
end
