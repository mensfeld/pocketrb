# frozen_string_literal: true

RSpec.describe Pocketrb::Tools::ReadFile do
  subject(:tool) { described_class.new(workspace: temp_workspace) }

  before do
    FileUtils.mkdir_p(temp_workspace)
    File.write(temp_workspace.join("test.txt"), "line 1\nline 2\nline 3\n")
  end

  describe "#name" do
    it "returns read_file" do
      expect(tool.name).to eq("read_file")
    end
  end

  describe "#execute" do
    context "with valid file" do
      it "reads file contents with line numbers" do
        result = tool.execute(path: "test.txt")

        expect(result).to include("1: line 1")
        expect(result).to include("2: line 2")
        expect(result).to include("3: line 3")
      end

      it "supports offset parameter" do
        result = tool.execute(path: "test.txt", offset: 2)

        expect(result).not_to include("1: line 1")
        expect(result).to include("2: line 2")
      end

      it "supports limit parameter" do
        result = tool.execute(path: "test.txt", limit: 1)

        expect(result).to include("1: line 1")
        expect(result).not_to include("2: line 2")
      end
    end

    context "with missing file" do
      it "raises ToolError" do
        expect { tool.execute(path: "nonexistent.txt") }.to raise_error(Pocketrb::ToolError)
      end
    end

    context "with path outside workspace" do
      it "raises ToolError" do
        expect { tool.execute(path: "/etc/passwd") }.to raise_error(Pocketrb::ToolError)
      end
    end
  end

  describe "#to_definition" do
    it "returns OpenAI-style tool definition" do
      definition = tool.to_definition

      expect(definition[:type]).to eq("function")
      expect(definition[:function][:name]).to eq("read_file")
      expect(definition[:function][:parameters][:properties]).to have_key(:path)
    end
  end
end
