# frozen_string_literal: true

RSpec.describe Pocketrb::Tools::WriteFile do
  let(:workspace) { Pathname.new(Dir.mktmpdir) }
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
      expect(tool.description).to include("Write content")
    end
  end

  describe "#parameters" do
    it "defines path and content parameters" do
      params = tool.parameters
      expect(params[:properties]).to have_key(:path)
      expect(params[:properties]).to have_key(:content)
      expect(params[:required]).to include("path", "content")
    end
  end

  describe "#execute" do
    context "with valid file path" do
      it "creates the file with content" do
        result = tool.execute(path: "test.txt", content: "Hello world")

        expect(result).to include("Wrote")
        expect(workspace.join("test.txt")).to exist
        expect(File.read(workspace.join("test.txt"))).to eq("Hello world")
      end

      it "creates parent directories if needed" do
        result = tool.execute(path: "subdir/nested/test.txt", content: "Content")

        expect(result).to include("Wrote")
        expect(workspace.join("subdir/nested/test.txt")).to exist
      end

      it "overwrites existing file" do
        File.write(workspace.join("test.txt"), "Old content")

        result = tool.execute(path: "test.txt", content: "New content")

        expect(result).to include("Wrote")
        expect(File.read(workspace.join("test.txt"))).to eq("New content")
      end

      it "reports line count and byte size" do
        result = tool.execute(path: "test.txt", content: "Line 1\nLine 2\nLine 3")

        expect(result).to match(/Wrote 3 lines/)
        expect(result).to match(/20 bytes/)
      end
    end

    context "with path outside workspace" do
      it "returns an error" do
        result = tool.execute(path: "/etc/passwd", content: "hack")

        expect(result).to include("Error:")
        expect(result).to include("outside workspace")
      end

      it "blocks parent directory traversal" do
        result = tool.execute(path: "../../../etc/passwd", content: "hack")

        expect(result).to include("Error:")
      end
    end

    context "with content exceeding maximum size" do
      it "returns an error" do
        large_content = "x" * (11 * 1024 * 1024) # 11MB (exceeds 10MB limit)

        result = tool.execute(path: "large.txt", content: large_content)

        expect(result).to include("Error:")
        expect(result).to include("maximum file size")
      end
    end

    context "with empty content" do
      it "creates an empty file" do
        result = tool.execute(path: "empty.txt", content: "")

        expect(result).to include("Wrote")
        expect(workspace.join("empty.txt")).to exist
        expect(File.read(workspace.join("empty.txt"))).to eq("")
      end
    end
  end
end
