# frozen_string_literal: true

RSpec.describe Pocketrb::Tools::WriteFileTool do
  let(:workspace) { Dir.mktmpdir }
  let(:tool) { described_class.new(workspace: workspace) }

  after do
    FileUtils.rm_rf(workspace)
  end

  describe "#name" do
    it "returns write_file" do
      expect(tool.name).to eq("write_file")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to be_a(String)
      expect(tool.description).to include("Write")
    end
  end

  describe "#parameters" do
    it "defines path parameter" do
      params = tool.parameters
      expect(params[:properties]).to have_key(:path)
      expect(params[:required]).to include("path")
    end

    it "defines content parameter" do
      params = tool.parameters
      expect(params[:properties]).to have_key(:content)
      expect(params[:required]).to include("content")
    end
  end

  describe "#execute" do
    it "writes content to file" do
      result = tool.execute(path: "test.txt", content: "Hello, World!")

      file_path = Pathname.new(workspace).join("test.txt")
      expect(file_path).to exist
      expect(file_path.read).to eq("Hello, World!")
      expect(result).to include("Wrote")
    end

    it "creates parent directories" do
      result = tool.execute(path: "subdir/nested/file.txt", content: "content")

      file_path = Pathname.new(workspace).join("subdir/nested/file.txt")
      expect(file_path).to exist
      expect(file_path.read).to eq("content")
      expect(result).to include("Wrote")
    end

    it "overwrites existing files" do
      file_path = Pathname.new(workspace).join("existing.txt")
      file_path.write("old content")

      tool.execute(path: "existing.txt", content: "new content")
      expect(file_path.read).to eq("new content")
    end

    it "handles empty content" do
      result = tool.execute(path: "empty.txt", content: "")

      file_path = Pathname.new(workspace).join("empty.txt")
      expect(file_path).to exist
      expect(file_path.read).to eq("")
      expect(result).to include("Wrote")
    end

    it "handles multiline content" do
      content = "Line 1\nLine 2\nLine 3"
      tool.execute(path: "multiline.txt", content: content)

      file_path = Pathname.new(workspace).join("multiline.txt")
      expect(file_path.read).to eq(content)
    end

    it "prevents path traversal outside workspace" do
      result = tool.execute(path: "../outside.txt", content: "test")
      # Should either prevent or normalize to workspace
      outside_file = Pathname.new(workspace).parent.join("outside.txt")
      expect(outside_file).not_to exist
    end

    it "prevents absolute paths outside workspace" do
      result = tool.execute(path: "/etc/passwd", content: "malicious")
      # Should be rejected or normalized to workspace
      expect(Pathname.new("/etc/passwd").read).not_to eq("malicious")
    end

    it "returns error for invalid paths" do
      result = tool.execute(path: "", content: "test")
      expect(result).to include("Error") || expect(result).to include("Invalid")
    end
  end

  describe "file metadata" do
    it "reports file size" do
      result = tool.execute(path: "test.txt", content: "Hello")
      expect(result).to include("5 bytes") || expect(result).to match(/\d+ bytes/)
    end
  end
end
