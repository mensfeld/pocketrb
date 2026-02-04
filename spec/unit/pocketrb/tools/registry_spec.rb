# frozen_string_literal: true

RSpec.describe Pocketrb::Tools::Registry do
  let(:registry) { described_class.new }
  let(:mock_tool) do
    Class.new(Pocketrb::Tools::Base) do
      def name
        "mock_tool"
      end

      def description
        "A mock tool"
      end

      def execute(arg1: nil)
        "Result: #{arg1}"
      end

      def parameters
        {
          type: "object",
          properties: {
            arg1: { type: "string" }
          },
          required: []
        }
      end
    end
  end

  describe "#register" do
    it "registers a tool instance" do
      tool = mock_tool.new
      registry.register(tool)

      expect(registry.exists?("mock_tool")).to be true
      expect(registry.get("mock_tool")).to eq(tool)
    end

    it "raises error for non-tool objects" do
      expect do
        registry.register("not a tool")
      end.to raise_error(ArgumentError, /must inherit from Tools::Base/)
    end
  end

  describe "#register_class" do
    it "instantiates and registers tool class" do
      registry.register_class(mock_tool)

      expect(registry.exists?("mock_tool")).to be true
      expect(registry.get("mock_tool")).to be_a(mock_tool)
    end

    it "passes context to tool instance" do
      registry_with_context = described_class.new(workspace: "/tmp")
      registry_with_context.register_class(mock_tool)

      tool = registry_with_context.get("mock_tool")
      expect(tool.context[:workspace]).to eq("/tmp")
    end
  end

  describe "#unregister" do
    it "removes a tool from registry" do
      registry.register_class(mock_tool)
      expect(registry.exists?("mock_tool")).to be true

      registry.unregister("mock_tool")
      expect(registry.exists?("mock_tool")).to be false
    end
  end

  describe "#get" do
    it "returns tool by name" do
      tool = mock_tool.new
      registry.register(tool)

      expect(registry.get("mock_tool")).to eq(tool)
    end

    it "returns nil for unknown tool" do
      expect(registry.get("nonexistent")).to be_nil
    end
  end

  describe "#exists?" do
    it "returns true for registered tool" do
      registry.register_class(mock_tool)
      expect(registry.exists?("mock_tool")).to be true
    end

    it "returns false for unregistered tool" do
      expect(registry.exists?("nonexistent")).to be false
    end
  end

  describe "#names" do
    it "returns array of tool names" do
      registry.register_class(mock_tool)
      expect(registry.names).to include("mock_tool")
    end

    it "returns empty array when no tools registered" do
      expect(registry.names).to eq([])
    end
  end

  describe "#size" do
    it "returns count of registered tools" do
      expect(registry.size).to eq(0)

      registry.register_class(mock_tool)
      expect(registry.size).to eq(1)
    end
  end

  describe "#clear!" do
    it "removes all tools" do
      registry.register_class(mock_tool)
      expect(registry.size).to eq(1)

      registry.clear!
      expect(registry.size).to eq(0)
    end
  end

  describe "#definitions" do
    before do
      registry.register_class(mock_tool)
    end

    it "returns array of tool definitions" do
      defs = registry.definitions

      expect(defs).to be_an(Array)
      expect(defs.first).to have_key(:type)
      expect(defs.first).to have_key(:function)
    end

    it "filters unavailable tools by default" do
      unavailable_tool = Class.new(Pocketrb::Tools::Base) do
        def name
          "unavailable"
        end

        def description
          "Not available"
        end

        def available?
          false
        end
      end

      registry.register_class(unavailable_tool)

      defs = registry.definitions(filter_unavailable: true)
      expect(defs.map { |d| d[:function][:name] }).not_to include("unavailable")
    end

    it "includes unavailable tools when filter is false" do
      unavailable_tool = Class.new(Pocketrb::Tools::Base) do
        def name
          "unavailable"
        end

        def description
          "Not available"
        end

        def available?
          false
        end
      end

      registry.register_class(unavailable_tool)

      defs = registry.definitions(filter_unavailable: false)
      expect(defs.map { |d| d[:function][:name] }).to include("unavailable")
    end
  end

  describe "#anthropic_definitions" do
    before do
      registry.register_class(mock_tool)
    end

    it "returns Anthropic-format definitions" do
      defs = registry.anthropic_definitions

      expect(defs).to be_an(Array)
      expect(defs.first).to have_key(:name)
      expect(defs.first).to have_key(:description)
      expect(defs.first).to have_key(:input_schema)
    end
  end

  describe "#execute" do
    before do
      registry.register_class(mock_tool)
    end

    it "executes tool with arguments" do
      result = registry.execute("mock_tool", { "arg1" => "test" })

      expect(result).to eq("Result: test")
    end

    it "raises error for unknown tool" do
      expect do
        registry.execute("nonexistent", {})
      end.to raise_error(Pocketrb::ToolError, /Unknown tool/)
    end

    it "raises error for unavailable tool" do
      unavailable_tool = Class.new(Pocketrb::Tools::Base) do
        def name
          "unavailable"
        end

        def description
          "Test"
        end

        def available?
          false
        end
      end

      registry.register_class(unavailable_tool)

      expect do
        registry.execute("unavailable", {})
      end.to raise_error(Pocketrb::ToolError, /not available/)
    end

    it "converts string keys to symbols" do
      result = registry.execute("mock_tool", { "arg1" => "value" })

      expect(result).to include("value")
    end

    it "filters unknown arguments" do
      result = registry.execute("mock_tool", {
                                  "arg1" => "valid",
                                  "unknown_arg" => "filtered"
                                })

      expect(result).to eq("Result: valid")
    end

    it "wraps tool exceptions in ToolError" do
      failing_tool = Class.new(Pocketrb::Tools::Base) do
        def name
          "failing"
        end

        def description
          "Fails"
        end

        def execute
          raise StandardError, "Intentional error"
        end
      end

      registry.register_class(failing_tool)

      expect do
        registry.execute("failing", {})
      end.to raise_error(Pocketrb::ToolError, /Tool execution failed/)
    end
  end

  describe "#available_tools" do
    it "returns only available tools" do
      available = Class.new(Pocketrb::Tools::Base) do
        def name
          "available"
        end

        def description
          "Available"
        end
      end

      unavailable = Class.new(Pocketrb::Tools::Base) do
        def name
          "unavailable"
        end

        def description
          "Not available"
        end

        def available?
          false
        end
      end

      registry.register_class(available)
      registry.register_class(unavailable)

      tools = registry.available_tools
      expect(tools.map(&:name)).to eq(["available"])
    end
  end

  describe "#update_context" do
    it "updates context for all registered tools" do
      registry.register_class(mock_tool)

      registry.update_context(new_key: "new_value")

      tool = registry.get("mock_tool")
      expect(tool.context[:new_key]).to eq("new_value")
    end

    it "merges with existing context" do
      registry_with_context = described_class.new(existing: "value")
      registry_with_context.register_class(mock_tool)

      registry_with_context.update_context(new: "data")

      tool = registry_with_context.get("mock_tool")
      expect(tool.context[:existing]).to eq("value")
      expect(tool.context[:new]).to eq("data")
    end
  end

  describe "#register_defaults!" do
    it "registers core tools" do
      registry.register_defaults!

      expect(registry.exists?("read_file")).to be true
      expect(registry.exists?("write_file")).to be true
      expect(registry.exists?("exec")).to be true
      expect(registry.size).to be > 5
    end
  end
end
