# frozen_string_literal: true

RSpec.describe Pocketrb::Providers::OpenRouter do
  let(:config) { { openrouter_api_key: "test-key" } }
  let(:provider) { described_class.new(config) }

  describe "#name" do
    it "returns openrouter" do
      expect(provider.name).to eq(:openrouter)
    end
  end

  describe "#default_model" do
    it "returns claude-sonnet-4" do
      expect(provider.default_model).to eq("anthropic/claude-sonnet-4")
    end
  end

  describe "#available_models" do
    it "returns popular models list" do
      models = provider.available_models

      expect(models).to include("anthropic/claude-sonnet-4")
      expect(models).to include("openai/gpt-4o")
      expect(models).to be_an(Array)
    end
  end

  describe "#supports?" do
    it "supports tools" do
      expect(provider.supports?(:tools)).to be true
    end

    it "supports streaming" do
      expect(provider.supports?(:streaming)).to be true
    end

    it "does not support vision" do
      expect(provider.supports?(:vision)).to be false
    end

    it "does not support thinking" do
      expect(provider.supports?(:thinking)).to be false
    end
  end

  describe "authentication" do
    context "without API key" do
      it "raises ConfigurationError" do
        expect do
          described_class.new({})
        end.to raise_error(Pocketrb::ConfigurationError, /openrouter_api_key/)
      end
    end

    context "with API key" do
      it "creates provider successfully" do
        expect { provider }.not_to raise_error
      end
    end
  end

  describe "#chat" do
    let(:messages) do
      [
        Pocketrb::Providers::Message.user("Hello")
      ]
    end

    let(:mock_response) do
      {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => "Hi there!"
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => {
          "prompt_tokens" => 10,
          "completion_tokens" => 5
        },
        "model" => "anthropic/claude-sonnet-4"
      }
    end

    before do
      stub_request(:post, "https://openrouter.ai/api/v1/chat/completions")
        .to_return(
          status: 200,
          body: mock_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "sends chat request to OpenRouter API" do
      response = provider.chat(messages: messages)

      expect(response.content).to eq("Hi there!")
      expect(response.model).to eq("anthropic/claude-sonnet-4")
    end

    it "includes usage information" do
      response = provider.chat(messages: messages)

      expect(response.usage.input_tokens).to eq(10)
      expect(response.usage.output_tokens).to eq(5)
    end

    it "uses default model when not specified" do
      provider.chat(messages: messages)

      expect(WebMock).to(have_requested(:post, "https://openrouter.ai/api/v1/chat/completions")
        .with { |req| JSON.parse(req.body)["model"] == "anthropic/claude-sonnet-4" })
    end

    it "uses custom model when specified" do
      provider.chat(messages: messages, model: "openai/gpt-4o")

      expect(WebMock).to(have_requested(:post, "https://openrouter.ai/api/v1/chat/completions")
        .with { |req| JSON.parse(req.body)["model"] == "openai/gpt-4o" })
    end

    it "includes tools in request when provided" do
      tools = [{ name: "test_tool", description: "Test" }]

      provider.chat(messages: messages, tools: tools)

      expect(WebMock).to(have_requested(:post, "https://openrouter.ai/api/v1/chat/completions")
        .with { |req| JSON.parse(req.body).key?("tools") && JSON.parse(req.body)["tools"].any? })
    end

    it "sets authorization header" do
      provider.chat(messages: messages)

      expect(WebMock).to have_requested(:post, "https://openrouter.ai/api/v1/chat/completions")
        .with(headers: { "Authorization" => "Bearer test-key" })
    end
  end

  describe "response parsing" do
    let(:messages) { [Pocketrb::Providers::Message.user("Test")] }

    context "with tool calls" do
      let(:tool_response) do
        {
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => "Let me check that",
                "tool_calls" => [
                  {
                    "id" => "call_123",
                    "type" => "function",
                    "function" => {
                      "name" => "search",
                      "arguments" => '{"query":"test"}'
                    }
                  }
                ]
              },
              "finish_reason" => "tool_calls"
            }
          ]
        }
      end

      before do
        stub_request(:post, "https://openrouter.ai/api/v1/chat/completions")
          .to_return(status: 200, body: tool_response.to_json)
      end

      it "parses tool calls" do
        response = provider.chat(messages: messages)

        expect(response.tool_calls).not_to be_empty
        expect(response.tool_calls.first.name).to eq("search")
        expect(response.tool_calls.first.id).to eq("call_123")
      end

      it "sets stop reason to tool_use" do
        response = provider.chat(messages: messages)

        expect(response.stop_reason).to eq(:tool_use)
      end
    end

    context "with max_tokens finish reason" do
      before do
        stub_request(:post, "https://openrouter.ai/api/v1/chat/completions")
          .to_return(status: 200, body: {
            "choices" => [
              {
                "message" => { "content" => "Response" },
                "finish_reason" => "length"
              }
            ]
          }.to_json)
      end

      it "sets stop reason to max_tokens" do
        response = provider.chat(messages: messages)

        expect(response.stop_reason).to eq(:max_tokens)
      end
    end

    context "with API error" do
      before do
        stub_request(:post, "https://openrouter.ai/api/v1/chat/completions")
          .to_return(status: 401, body: { "error" => "Invalid API key" }.to_json)
      end

      it "raises ProviderError" do
        expect do
          provider.chat(messages: messages)
        end.to raise_error(Pocketrb::ProviderError, /Invalid API key/)
      end
    end
  end

  describe "message formatting" do
    it "formats system messages" do
      msg = Pocketrb::Providers::Message.system("You are helpful")
      formatted = provider.send(:format_message, msg)

      expect(formatted).to eq({ role: "system", content: "You are helpful" })
    end

    it "formats user messages" do
      msg = Pocketrb::Providers::Message.user("Hello")
      formatted = provider.send(:format_message, msg)

      expect(formatted).to eq({ role: "user", content: "Hello" })
    end

    it "formats assistant messages with tool calls" do
      tool_call = Pocketrb::Providers::ToolCall.new(
        id: "call_1",
        name: "search",
        arguments: { query: "test" }
      )
      msg = Pocketrb::Providers::Message.assistant("Searching", tool_calls: [tool_call])
      formatted = provider.send(:format_message, msg)

      expect(formatted[:role]).to eq("assistant")
      expect(formatted[:tool_calls]).to be_an(Array)
      expect(formatted[:tool_calls].first[:id]).to eq("call_1")
    end

    it "formats tool result messages" do
      msg = Pocketrb::Providers::Message.tool_result(
        tool_call_id: "call_1",
        name: "search",
        content: "Results"
      )
      formatted = provider.send(:format_message, msg)

      expect(formatted[:role]).to eq("tool")
      expect(formatted[:tool_call_id]).to eq("call_1")
      expect(formatted[:content]).to eq("Results")
    end
  end
end
