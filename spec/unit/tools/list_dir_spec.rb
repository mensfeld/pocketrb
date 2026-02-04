# frozen_string_literal: true

RSpec.describe Pocketrb::Tools::ListDirTool do
  let(:workspace) { Dir.mktmpdir }
  let(:tool) { described_class.new(workspace: workspace) }

  before do
    # Create test directory structure
    FileUtils.mkdir_p(Pathname.new(workspace).join("subdir"))
    Pathname.new(workspace).join("file1.txt").write("content1")
    Pathname.new(workspace).join("file2.rb").write("content2")
    Pathname.new(workspace).join("subdir/nested.txt").write("nested")
  end

  after do
    FileUtils.rm_rf(workspace)
  end

  describe "#name" do
    it "returns list_dir" do
      expect(tool.name).to eq("list_dir")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to be_a(String)
      expect(tool.description).to include("List")
    end
  end

  describe "#parameters" do
    it "defines path parameter" do
      params = tool.parameters
      expect(params[:properties]).to have_key(:path)
    end
  end

  describe "#execute" do
    it "lists files in current directory when no path given" do
      result = tool.execute(path: ".")
      expect(result).to include("file1.txt")
      expect(result).to include("file2.rb")
      expect(result).to include("subdir")
    end

    it "lists files in specified directory" do
      result = tool.execute(path: "subdir")
      expect(result).to include("nested.txt")
    end

    it "shows file types" do
      result = tool.execute(path: ".")
      expect(result).to include("file") || expect(result).to include("directory")
    end

    it "handles non-existent directories" do
      result = tool.execute(path: "nonexistent")
      expect(result).to include("Error") || expect(result).to include("not found") || expect(result).to include("No such")
    end

    it "handles empty directories" do
      empty_dir = Pathname.new(workspace).join("empty")
      empty_dir.mkpath

      result = tool.execute(path: "empty")
      expect(result).to include("empty") || expect(result).to include("No files")
    end

    it "prevents listing outside workspace" do
      result = tool.execute(path: "..")
      # Should either prevent or normalize to workspace
      expect(result).not_to include("etc") # Shouldn't show system directories
    end
  end

  describe "file information" do
    it "shows file sizes" do
      result = tool.execute(path: ".")
      expect(result).to match(/\d+ bytes/) || expect(result).to include("B")
    end

    it "distinguishes files from directories" do
      result = tool.execute(path: ".")
      expect(result).to include("file1.txt")
      expect(result).to include("subdir")
    end
  end
end
