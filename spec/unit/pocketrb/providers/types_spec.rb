# frozen_string_literal: true

RSpec.describe Pocketrb::Providers do
  describe "LLMResponse" do
    let(:usage) do
      described_class::Usage.new(
        input_tokens: 100,
        output_tokens: 50
      )
    end

    let(:tool_call) do
      described_class::ToolCall.new(
        id: "call_123",
        name: "read_file",
        arguments: { path: "test.txt" }
      )
    end

    describe "#initialize" do
      it "creates response with required fields" do
        response = described_class::LLMResponse.new(
          content: "Hello",
          usage: usage,
          model: "claude-sonnet-4"
        )

        expect(response.content).to eq("Hello")
        expect(response.usage).to eq(usage)
        expect(response.model).to eq("claude-sonnet-4")
      end

      it "defaults tool_calls to empty array" do
        response = described_class::LLMResponse.new(content: "Hello")

        expect(response.tool_calls).to eq([])
      end

      it "defaults stop_reason to end_turn" do
        response = described_class::LLMResponse.new(content: "Hello")

        expect(response.stop_reason).to eq(:end_turn)
      end

      it "defaults thinking to nil" do
        response = described_class::LLMResponse.new(content: "Hello")

        expect(response.thinking).to be_nil
      end
    end

    describe "#has_tool_calls?" do
      it "returns false when tool_calls is empty" do
        response = described_class::LLMResponse.new(content: "Hello")

        expect(response.has_tool_calls?).to be false
      end

      it "returns true when tool_calls are present" do
        response = described_class::LLMResponse.new(
          content: "Using tool",
          tool_calls: [tool_call]
        )

        expect(response.has_tool_calls?).to be true
      end
    end

    describe "#has_content?" do
      it "returns false when content is nil" do
        response = described_class::LLMResponse.new(content: nil)

        expect(response).not_to have_content
      end

      it "returns false when content is empty string" do
        response = described_class::LLMResponse.new(content: "")

        expect(response.has_content?).to be false
      end

      it "returns true when content is present" do
        response = described_class::LLMResponse.new(content: "Hello")

        expect(response.has_content?).to be true
      end
    end

    describe "#has_thinking?" do
      it "returns false when thinking is nil" do
        response = described_class::LLMResponse.new(content: "Hello")

        expect(response).not_to have_thinking
      end

      it "returns false when thinking is empty" do
        response = described_class::LLMResponse.new(
          content: "Hello",
          thinking: ""
        )

        expect(response.has_thinking?).to be false
      end

      it "returns true when thinking is present" do
        response = described_class::LLMResponse.new(
          content: "Hello",
          thinking: "Let me think about this..."
        )

        expect(response.has_thinking?).to be true
      end
    end
  end

  describe "ToolCall" do
    describe "#initialize" do
      it "creates tool call with hash arguments" do
        tool_call = described_class::ToolCall.new(
          id: "call_123",
          name: "read_file",
          arguments: { path: "test.txt" }
        )

        expect(tool_call.id).to eq("call_123")
        expect(tool_call.name).to eq("read_file")
        expect(tool_call.arguments).to eq({ path: "test.txt" })
      end

      it "parses JSON string arguments" do
        tool_call = described_class::ToolCall.new(
          id: "call_123",
          name: "read_file",
          arguments: '{"path":"test.txt"}'
        )

        expect(tool_call.arguments).to eq({ "path" => "test.txt" })
      end

      it "handles invalid JSON by using empty hash" do
        tool_call = described_class::ToolCall.new(
          id: "call_123",
          name: "read_file",
          arguments: "invalid json"
        )

        expect(tool_call.arguments).to eq({})
      end
    end
  end

  describe "Usage" do
    describe "#initialize" do
      it "creates usage with token counts" do
        usage = described_class::Usage.new(
          input_tokens: 100,
          output_tokens: 50
        )

        expect(usage.input_tokens).to eq(100)
        expect(usage.output_tokens).to eq(50)
      end

      it "defaults input_tokens to 0" do
        usage = described_class::Usage.new

        expect(usage.input_tokens).to eq(0)
      end

      it "defaults output_tokens to 0" do
        usage = described_class::Usage.new

        expect(usage.output_tokens).to eq(0)
      end

      it "defaults cache_read to nil" do
        usage = described_class::Usage.new

        expect(usage.cache_read).to be_nil
      end

      it "defaults cache_write to nil" do
        usage = described_class::Usage.new

        expect(usage.cache_write).to be_nil
      end

      it "accepts cache statistics" do
        usage = described_class::Usage.new(
          input_tokens: 100,
          output_tokens: 50,
          cache_read: 75,
          cache_write: 25
        )

        expect(usage.cache_read).to eq(75)
        expect(usage.cache_write).to eq(25)
      end
    end

    describe "#total_tokens" do
      it "sums input and output tokens" do
        usage = described_class::Usage.new(
          input_tokens: 100,
          output_tokens: 50
        )

        expect(usage.total_tokens).to eq(150)
      end

      it "handles zero tokens" do
        usage = described_class::Usage.new

        expect(usage.total_tokens).to eq(0)
      end
    end
  end

  describe "Message" do
    describe ".system" do
      it "creates system message" do
        message = described_class::Message.system("You are a helpful assistant")

        expect(message.role).to eq(described_class::Role::SYSTEM)
        expect(message.content).to eq("You are a helpful assistant")
      end
    end

    describe ".user" do
      it "creates user message with text content" do
        message = described_class::Message.user("Hello")

        expect(message.role).to eq(described_class::Role::USER)
        expect(message.content).to eq("Hello")
      end

      it "creates user message with media as content blocks" do
        media = Pocketrb::Bus::Media.new(
          type: :image,
          path: "/path/to/image.png",
          mime_type: "image/png"
        )

        message = described_class::Message.user("Check this image", media: [media])

        expect(message.role).to eq(described_class::Role::USER)
        expect(message.content).to be_an(Array)
        expect(message.content.first[:type]).to eq("text")
        expect(message.content.first[:text]).to eq("Check this image")
        expect(message.content.last[:type]).to eq("media")
      end

      it "creates media-only message when content is empty" do
        media = Pocketrb::Bus::Media.new(
          type: :image,
          path: "/path/to/image.png",
          mime_type: "image/png"
        )

        message = described_class::Message.user("", media: [media])

        expect(message.content).to be_an(Array)
        expect(message.content.length).to eq(1)
        expect(message.content.first[:type]).to eq("media")
      end

      it "creates text-only message when media is nil" do
        message = described_class::Message.user("Hello", media: nil)

        expect(message.content).to eq("Hello")
      end

      it "creates text-only message when media is empty" do
        message = described_class::Message.user("Hello", media: [])

        expect(message.content).to eq("Hello")
      end
    end

    describe ".assistant" do
      it "creates assistant message" do
        message = described_class::Message.assistant("I can help")

        expect(message.role).to eq(described_class::Role::ASSISTANT)
        expect(message.content).to eq("I can help")
      end

      it "includes tool_calls when provided" do
        tool_call = described_class::ToolCall.new(
          id: "call_123",
          name: "read_file",
          arguments: { path: "test.txt" }
        )

        message = described_class::Message.assistant("Using tool", tool_calls: [tool_call])

        expect(message.tool_calls).to eq([tool_call])
      end
    end

    describe ".tool_result" do
      it "creates tool result message" do
        message = described_class::Message.tool_result(
          tool_call_id: "call_123",
          name: "read_file",
          content: "File contents"
        )

        expect(message.role).to eq(described_class::Role::TOOL)
        expect(message.tool_call_id).to eq("call_123")
        expect(message.name).to eq("read_file")
        expect(message.content).to eq("File contents")
      end
    end
  end

  describe "Role" do
    it "defines SYSTEM constant" do
      expect(described_class::Role::SYSTEM).to eq("system")
    end

    it "defines USER constant" do
      expect(described_class::Role::USER).to eq("user")
    end

    it "defines ASSISTANT constant" do
      expect(described_class::Role::ASSISTANT).to eq("assistant")
    end

    it "defines TOOL constant" do
      expect(described_class::Role::TOOL).to eq("tool")
    end
  end
end
