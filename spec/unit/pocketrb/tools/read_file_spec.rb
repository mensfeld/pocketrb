# frozen_string_literal: true

RSpec.describe Pocketrb::Tools::ReadFile do
  let(:workspace) { Pathname.new(Dir.mktmpdir) }
  let(:context) { { workspace: workspace } }
  let(:tool) { described_class.new(context) }

  after do
    FileUtils.rm_rf(workspace)
  end

  describe "#name" do
    it "returns read_file" do
      expect(tool.name).to eq("read_file")
    end
  end

  describe "#description" do
    it "returns description" do
      expect(tool.description).to include("Read the contents")
    end
  end

  describe "#parameters" do
    it "requires path parameter" do
      expect(tool.parameters[:required]).to eq(["path"])
    end

    it "includes path, offset, and limit properties" do
      props = tool.parameters[:properties]

      expect(props).to have_key(:path)
      expect(props).to have_key(:offset)
      expect(props).to have_key(:limit)
    end
  end

  describe "#execute" do
    context "with simple text file" do
      before do
        file = workspace.join("test.txt")
        file.write("line 1\nline 2\nline 3\n")
      end

      it "reads entire file" do
        result = tool.execute(path: "test.txt")

        expect(result).to include("1: line 1")
        expect(result).to include("2: line 2")
        expect(result).to include("3: line 3")
      end

      it "adds line numbers" do
        result = tool.execute(path: "test.txt")

        expect(result).to start_with("1: ")
      end

      it "preserves newlines" do
        result = tool.execute(path: "test.txt")

        expect(result.scan("\n").count).to eq(3)
      end
    end

    context "with offset parameter" do
      before do
        file = workspace.join("large.txt")
        file.write((1..10).map { |n| "line #{n}\n" }.join)
      end

      it "starts reading from offset" do
        result = tool.execute(path: "large.txt", offset: 5)

        expect(result).to include("5: line 5")
        expect(result).not_to include("4: line 4")
      end

      it "adjusts line numbers based on offset" do
        result = tool.execute(path: "large.txt", offset: 3)

        expect(result).to start_with("3: ")
      end

      it "reads from beginning when offset is 1" do
        result = tool.execute(path: "large.txt", offset: 1)

        expect(result).to start_with("1: ")
        expect(result).to include("10: line 10")
      end
    end

    context "with limit parameter" do
      before do
        file = workspace.join("large.txt")
        file.write((1..10).map { |n| "line #{n}\n" }.join)
      end

      it "reads only specified number of lines" do
        result = tool.execute(path: "large.txt", limit: 3)

        expect(result).to include("1: line 1")
        expect(result).to include("3: line 3")
        expect(result).not_to include("4: line 4")
      end

      it "counts lines correctly" do
        result = tool.execute(path: "large.txt", limit: 5)
        lines = result.split("\n")

        expect(lines.length).to eq(5)
      end
    end

    context "with both offset and limit" do
      before do
        file = workspace.join("large.txt")
        file.write((1..20).map { |n| "line #{n}\n" }.join)
      end

      it "reads slice of file" do
        result = tool.execute(path: "large.txt", offset: 10, limit: 5)

        expect(result).to include("10: line 10")
        expect(result).to include("14: line 14")
        expect(result).not_to include("9: line 9")
        expect(result).not_to include("15: line 15")
      end

      it "uses correct line numbering" do
        result = tool.execute(path: "large.txt", offset: 15, limit: 3)

        expect(result).to start_with("15: ")
      end
    end

    context "with absolute path" do
      it "reads file with absolute path" do
        file = workspace.join("abs_test.txt")
        file.write("absolute content\n")

        result = tool.execute(path: file.to_s)

        expect(result).to include("absolute content")
      end
    end

    context "with subdirectory" do
      it "reads file in subdirectory" do
        subdir = workspace.join("subdir")
        subdir.mkpath
        file = subdir.join("nested.txt")
        file.write("nested content\n")

        result = tool.execute(path: "subdir/nested.txt")

        expect(result).to include("nested content")
      end
    end

    context "with error conditions" do
      it "raises error for non-existent file" do
        expect do
          tool.execute(path: "nonexistent.txt")
        end.to raise_error(Pocketrb::ToolError, /does not exist/)
      end

      it "returns error for directory" do
        subdir = workspace.join("subdir")
        subdir.mkpath

        result = tool.execute(path: "subdir")

        expect(result).to include("Error:")
        expect(result).to include("Not a file")
      end

      it "raises error for path outside workspace" do
        expect do
          tool.execute(path: "../../etc/passwd")
        end.to raise_error(Pocketrb::ToolError, /outside workspace/)
      end
    end

    context "with special characters" do
      it "handles UTF-8 content" do
        file = workspace.join("utf8.txt")
        file.write("Hello 世界\n")

        result = tool.execute(path: "utf8.txt")

        expect(result).to include("世界")
      end

      it "handles empty file" do
        file = workspace.join("empty.txt")
        file.write("")

        result = tool.execute(path: "empty.txt")

        expect(result).to eq("")
      end

      it "handles file with no trailing newline" do
        file = workspace.join("no_newline.txt")
        file.write("content without newline")

        result = tool.execute(path: "no_newline.txt")

        expect(result).to include("1: content without newline")
      end
    end
  end
end
