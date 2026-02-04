# frozen_string_literal: true

RSpec.describe Pocketrb::Tools::ListDir do
  let(:workspace) { Pathname.new(Dir.mktmpdir) }
  let(:tool) { described_class.new(workspace: workspace) }

  before do
    # Create test directory structure
    FileUtils.mkdir_p(workspace.join("subdir1"))
    FileUtils.mkdir_p(workspace.join("subdir2/nested"))
    File.write(workspace.join("file1.txt"), "content")
    File.write(workspace.join("file2.rb"), "code")
    File.write(workspace.join("subdir1/file3.txt"), "more")
    File.write(workspace.join(".hidden"), "secret")
  end

  after do
    FileUtils.rm_rf(workspace)
  end

  describe "#name" do
    it "returns list_dir" do
      expect(tool.name).to eq("list_dir")
    end
  end

  describe "#execute" do
    context "without arguments" do
      it "lists workspace root contents" do
        result = tool.execute

        expect(result).to include("file1.txt")
        expect(result).to include("file2.rb")
        expect(result).to include("subdir1/")
        expect(result).to include("subdir2/")
      end

      it "excludes hidden files by default" do
        result = tool.execute

        expect(result).not_to include(".hidden")
      end
    end

    context "with include_hidden: true" do
      it "includes hidden files" do
        result = tool.execute(include_hidden: true)

        expect(result).to include(".hidden")
      end
    end

    context "with specific path" do
      it "lists that directory" do
        result = tool.execute(path: "subdir1")

        expect(result).to include("file3.txt")
        expect(result).not_to include("file1.txt")
      end
    end

    context "with recursive: true" do
      it "lists all nested contents" do
        result = tool.execute(recursive: true)

        expect(result).to include("file1.txt")
        expect(result).to include("subdir1/file3.txt")
        expect(result).to include("subdir2/nested/")
      end
    end

    context "with pattern" do
      it "filters by glob pattern" do
        result = tool.execute(pattern: "*.txt")

        expect(result).to include("file1.txt")
        expect(result).not_to include("file2.rb")
      end

      it "supports recursive pattern" do
        result = tool.execute(pattern: "*.txt", recursive: true)

        expect(result).to include("file1.txt")
        expect(result).to include("file3.txt")
      end
    end

    context "with empty directory" do
      it "returns empty message" do
        FileUtils.mkdir_p(workspace.join("empty"))

        result = tool.execute(path: "empty")

        expect(result).to include("empty")
      end
    end

    context "with non-directory path" do
      it "returns an error" do
        result = tool.execute(path: "file1.txt")

        expect(result).to include("Error:")
        expect(result).to include("Not a directory")
      end
    end

    context "with output format" do
      it "includes file size and modification time" do
        result = tool.execute

        expect(result).to match(/file1\.txt.*\d+\.\d+[KMB]/)
        expect(result).to match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}/)
      end

      it "marks directories with trailing slash" do
        result = tool.execute

        expect(result).to include("subdir1/")
      end
    end
  end
end
