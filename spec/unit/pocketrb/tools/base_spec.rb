# frozen_string_literal: true

# Concrete test implementation for Base specs
class TestTool < Pocketrb::Tools::Base
  def name
    "test_tool"
  end

  def description
    "A test tool"
  end

  def execute(**kwargs)
    "executed with #{kwargs.inspect}"
  end
end

RSpec.describe Pocketrb::Tools::Base do
  let(:workspace) { Pathname.new(Dir.mktmpdir) }
  let(:bus) { instance_double(Pocketrb::Bus::MessageBus) }
  let(:context) { { workspace: workspace, bus: bus } }
  let(:tool) { TestTool.new(context) }

  after do
    FileUtils.rm_rf(workspace)
  end

  describe "#initialize" do
    it "stores context" do
      expect(tool.context).to eq(context)
    end

    it "accepts empty context" do
      t = TestTool.new

      expect(t.context).to eq({})
    end
  end

  describe "#name" do
    it "raises NotImplementedError for base class" do
      base_tool = described_class.new

      expect { base_tool.name }.to raise_error(NotImplementedError, /name must be implemented/)
    end

    it "can be implemented by subclass" do
      expect(tool.name).to eq("test_tool")
    end
  end

  describe "#description" do
    it "raises NotImplementedError for base class" do
      base_tool = described_class.new

      expect { base_tool.description }.to raise_error(NotImplementedError, /description must be implemented/)
    end

    it "can be implemented by subclass" do
      expect(tool.description).to eq("A test tool")
    end
  end

  describe "#parameters" do
    it "returns default empty schema" do
      expect(tool.parameters).to eq({
                                      type: "object",
                                      properties: {},
                                      required: []
                                    })
    end
  end

  describe "#execute" do
    it "raises NotImplementedError for base class" do
      base_tool = described_class.new

      expect { base_tool.execute }.to raise_error(NotImplementedError, /execute must be implemented/)
    end

    it "can be implemented by subclass" do
      result = tool.execute(arg1: "value1")

      expect(result).to include("executed")
      expect(result).to include("arg1")
    end
  end

  describe "#available?" do
    it "returns true by default" do
      expect(tool.available?).to be true
    end
  end

  describe "#to_definition" do
    it "returns OpenAI/Anthropic tool format" do
      definition = tool.to_definition

      expect(definition[:type]).to eq("function")
      expect(definition[:function][:name]).to eq("test_tool")
      expect(definition[:function][:description]).to eq("A test tool")
      expect(definition[:function][:parameters]).to eq(tool.parameters)
    end
  end

  describe "#to_anthropic_definition" do
    it "returns Anthropic-native tool format" do
      definition = tool.to_anthropic_definition

      expect(definition[:name]).to eq("test_tool")
      expect(definition[:description]).to eq("A test tool")
      expect(definition[:input_schema]).to eq(tool.parameters)
    end
  end

  describe "#success" do
    it "returns message as string" do
      result = tool.send(:success, "Operation completed")

      expect(result).to eq("Operation completed")
    end

    it "converts non-strings to strings" do
      result = tool.send(:success, 123)

      expect(result).to eq("123")
    end
  end

  describe "#error" do
    it "returns error message with prefix" do
      result = tool.send(:error, "Something went wrong")

      expect(result).to eq("Error: Something went wrong")
    end
  end

  describe "#workspace" do
    it "returns workspace from context" do
      expect(tool.send(:workspace)).to eq(workspace)
    end

    it "returns nil when no workspace in context" do
      tool_no_workspace = TestTool.new({})

      expect(tool_no_workspace.send(:workspace)).to be_nil
    end
  end

  describe "#bus" do
    it "returns bus from context" do
      expect(tool.send(:bus)).to eq(bus)
    end

    it "returns nil when no bus in context" do
      tool_no_bus = TestTool.new({})

      expect(tool_no_bus.send(:bus)).to be_nil
    end
  end

  describe "#resolve_path" do
    it "returns absolute paths as-is" do
      absolute = "/absolute/path/file.txt"
      resolved = tool.send(:resolve_path, absolute)

      expect(resolved).to eq(Pathname.new(absolute))
    end

    it "joins relative paths with workspace" do
      resolved = tool.send(:resolve_path, "relative/file.txt")

      expect(resolved).to eq(workspace.join("relative/file.txt"))
    end

    it "returns relative path when no workspace" do
      tool_no_workspace = TestTool.new({})
      resolved = tool_no_workspace.send(:resolve_path, "file.txt")

      expect(resolved).to eq(Pathname.new("file.txt"))
    end
  end

  describe "#path_allowed?" do
    it "returns true for paths within workspace" do
      path = "subdir/file.txt"

      expect(tool.send(:path_allowed?, path)).to be true
    end

    it "returns false for paths outside workspace" do
      path = "../../etc/passwd"

      expect(tool.send(:path_allowed?, path)).to be false
    end

    it "returns false for absolute paths outside workspace" do
      path = "/etc/passwd"

      expect(tool.send(:path_allowed?, path)).to be false
    end

    it "returns true when no workspace (no restriction)" do
      tool_no_workspace = TestTool.new({})

      expect(tool_no_workspace.send(:path_allowed?, "/any/path")).to be true
    end

    it "allows workspace root itself" do
      path = "."

      expect(tool.send(:path_allowed?, path)).to be true
    end
  end

  describe "#validate_path!" do
    it "returns resolved path for valid existing file" do
      file = workspace.join("test.txt")
      file.write("content")

      resolved = tool.send(:validate_path!, "test.txt")

      expect(resolved).to eq(file)
    end

    it "raises ToolError for path outside workspace" do
      expect do
        tool.send(:validate_path!, "../../etc/passwd")
      end.to raise_error(Pocketrb::ToolError, /outside workspace/)
    end

    it "raises ToolError for non-existent path when must_exist is true" do
      expect do
        tool.send(:validate_path!, "nonexistent.txt", must_exist: true)
      end.to raise_error(Pocketrb::ToolError, /does not exist/)
    end

    it "allows non-existent path when must_exist is false" do
      resolved = tool.send(:validate_path!, "new_file.txt", must_exist: false)

      expect(resolved).to eq(workspace.join("new_file.txt"))
    end

    it "allows absolute paths within workspace when must_exist is false" do
      absolute = workspace.join("subdir/file.txt").to_s

      resolved = tool.send(:validate_path!, absolute, must_exist: false)

      expect(resolved.to_s).to eq(absolute)
    end
  end
end
