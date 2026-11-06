# frozen_string_literal: true

RSpec.describe Pocketrb::Providers::RubyLLMProvider do
  let(:endpoint) { "https://api.anthropic.com/v1/messages" }
  let(:provider) { described_class.new(anthropic_api_key: "test-key") }
  let(:messages) do
    [
      Pocketrb::Providers::Message.system("You are helpful"),
      Pocketrb::Providers::Message.user("Hello")
    ]
  end

  let(:mock_response) do
    {
      "id" => "msg_1",
      "type" => "message",
      "role" => "assistant",
      "model" => "claude-sonnet-5-5",
      "content" => [{ "type" => "text", "text" => "Hi there!" }],
      "stop_reason" => "end_turn",
      "usage" => { "input_tokens" => 10, "output_tokens" => 5 }
    }
  end

  before do
    stub_request(:post, endpoint).to_return(
      status: 200,
      body: mock_response.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  describe "#name" do
    it "returns ruby_llm" do
      expect(provider.name).to eq(:ruby_llm)
    end
  end

  describe "#chat" do
    it "returns the parsed response" do
      response = provider.chat(messages: messages)

      expect(response).to have_attributes(content: "Hi there!", stop_reason: :end_turn, model: "claude-sonnet-5-5")
      expect(response.usage).to have_attributes(input_tokens: 10, output_tokens: 5)
    end

    it "sends one request with the system prompt and the user message" do
      provider.chat(messages: messages)

      expect(WebMock).to(have_requested(:post, endpoint).once.with do |req|
        body = JSON.parse(req.body)
        body["system"].to_s.include?("You are helpful") &&
          body["messages"] == [{ "role" => "user", "content" => [{ "type" => "text", "text" => "Hello" }] }]
      end)
    end

    it "sends the API key from the provider config" do
      provider.chat(messages: messages)

      expect(WebMock).to have_requested(:post, endpoint).with(headers: { "x-api-key" => "test-key" })
    end

    it "omits temperature for a model that rejects it" do
      provider.chat(messages: messages)

      expect(WebMock).to(have_requested(:post, endpoint).with { |req| !JSON.parse(req.body).key?("temperature") })
    end

    it "sends temperature and max_tokens for a model that accepts them" do
      provider.chat(messages: messages, model: "claude-haiku-4-5", temperature: 0.2, max_tokens: 100)

      expect(WebMock).to(have_requested(:post, endpoint).with do |req|
        JSON.parse(req.body).slice("temperature", "max_tokens", "model") ==
          { "temperature" => 0.2, "max_tokens" => 100, "model" => "claude-haiku-4-5" }
      end)
    end

    it "sends every system message" do
      provider.chat(messages: [Pocketrb::Providers::Message.system("Rule one")] + messages)

      expect(WebMock).to(have_requested(:post, endpoint).with do |req|
        system = JSON.parse(req.body)["system"].to_s
        system.include?("Rule one") && system.include?("You are helpful")
      end)
    end

    it "sends thinking without temperature and maps the thinking text" do
      stub_request(:post, endpoint).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: mock_response.merge(
          "content" => [
            { "type" => "thinking", "thinking" => "Let me think", "signature" => "sig" },
            { "type" => "text", "text" => "Hi there!" }
          ]
        ).to_json
      )

      response = provider.chat(messages: messages, model: "claude-haiku-4-5", thinking: true)

      expect(response.thinking).to eq("Let me think")
      expect(WebMock).to(have_requested(:post, endpoint).with do |req|
        body = JSON.parse(req.body)
        body.key?("thinking") && !body.key?("temperature")
      end)
    end

    it "maps cache usage and the max_tokens stop reason" do
      stub_request(:post, endpoint).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: mock_response.merge(
          "stop_reason" => "max_tokens",
          "usage" => { "input_tokens" => 10, "output_tokens" => 5, "cache_read_input_tokens" => 7, "cache_creation_input_tokens" => 3 }
        ).to_json
      )

      response = provider.chat(messages: messages)

      expect(response.stop_reason).to eq(:max_tokens)
      expect(response.usage).to have_attributes(cache_read: 7, cache_write: 3)
    end

    context "with media" do
      let(:png) { Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==") }

      def media(**attrs)
        Pocketrb::Bus::Media.new(type: :image, path: nil, mime_type: "image/png", filename: "pixel.png", **attrs)
      end

      def user_content(req)
        JSON.parse(req.body)["messages"].last["content"]
      end

      it "sends inline image data as an image block" do
        provider.chat(messages: [Pocketrb::Providers::Message.user("Look", media: [media(data: Base64.strict_encode64(png))])])

        expect(WebMock).to(have_requested(:post, endpoint).with do |req|
          content = user_content(req)
          content.any? { |c| c["type"] == "image" } && content.include?({ "type" => "text", "text" => "Look" })
        end)
      end

      it "sends an image file as an image block" do
        path = temp_workspace.join("pixel.png").to_s
        File.binwrite(path, png)

        provider.chat(messages: [Pocketrb::Providers::Message.user("Look", media: [media(path: path)])])

        expect(WebMock).to(have_requested(:post, endpoint).with { |req| user_content(req).any? { |c| c["type"] == "image" } })
      end

      it "sends placeholder text for an image when the model has no image input" do
        openai = "https://api.openai.com/v1/responses"
        stub_request(:post, openai).to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            "id" => "resp_1",
            "object" => "response",
            "model" => "gpt-4",
            "output" => [{ "type" => "message", "role" => "assistant", "content" => [{ "type" => "output_text", "text" => "ok" }] }],
            "usage" => { "input_tokens" => 1, "output_tokens" => 1 }
          }.to_json
        )

        described_class.new(openai_api_key: "test-key").chat(
          messages: [Pocketrb::Providers::Message.user("Look", media: [media(data: Base64.strict_encode64(png))])],
          model: "gpt-4"
        )

        expect(WebMock).to(have_requested(:post, openai).with do |req|
          JSON.parse(req.body)["input"].to_json.include?("Look\\n[Attached: pixel.png (image/png)]") && !req.body.include?("input_image")
        end)
      end

      it "sends placeholder text for audio" do
        audio = Pocketrb::Bus::Media.new(type: :audio, path: "/tmp/voice.ogg", mime_type: "audio/ogg", filename: "voice.ogg")

        provider.chat(messages: [Pocketrb::Providers::Message.user("Listen", media: [audio])])

        expect(WebMock).to(have_requested(:post, endpoint).with do |req|
          user_content(req) == [{ "type" => "text", "text" => "Listen\n[Attached: voice.ogg (audio/ogg)]" }]
        end)
      end

      it "sends placeholder text for a missing image file" do
        provider.chat(messages: [Pocketrb::Providers::Message.user("Look", media: [media(path: "/nonexistent/pixel.png")])])

        expect(WebMock).to(have_requested(:post, endpoint).with do |req|
          user_content(req) == [{ "type" => "text", "text" => "Look\n[Image not available]" }]
        end)
      end
    end

    context "with tools" do
      let(:tools) do
        [
          {
            type: "function",
            function: {
              name: "read_file",
              description: "Read a file",
              parameters: { type: "object", properties: { path: { type: "string" } }, required: ["path"] }
            }
          }
        ]
      end

      let(:mock_response) do
        {
          "id" => "msg_2",
          "type" => "message",
          "role" => "assistant",
          "model" => "claude-sonnet-5-5",
          "content" => [
            { "type" => "text", "text" => "Reading it." },
            { "type" => "tool_use", "id" => "toolu_1", "name" => "read_file", "input" => { "path" => "a.txt" } }
          ],
          "stop_reason" => "tool_use",
          "usage" => { "input_tokens" => 20, "output_tokens" => 8 }
        }
      end

      it "sends the tool definitions" do
        provider.chat(messages: messages, tools: tools)

        expect(WebMock).to(have_requested(:post, endpoint).with do |req|
          JSON.parse(req.body)["tools"] == [
            {
              "name" => "read_file",
              "description" => "Read a file",
              "input_schema" => { "type" => "object", "properties" => { "path" => { "type" => "string" } }, "required" => ["path"] }
            }
          ]
        end)
      end

      it "returns tool calls without executing them" do
        response = provider.chat(messages: messages, tools: tools)

        expect(response.stop_reason).to eq(:tool_use)
        expect(response.tool_calls).to eq(
          [Pocketrb::Providers::ToolCall.new(id: "toolu_1", name: "read_file", arguments: { "path" => "a.txt" })]
        )
        expect(WebMock).to have_requested(:post, endpoint).once
      end

      it "sends the earlier tool call and its result in the next turn" do
        history = messages + [
          Pocketrb::Providers::Message.assistant(
            "Reading it.",
            tool_calls: [Pocketrb::Providers::ToolCall.new(id: "toolu_1", name: "read_file", arguments: { "path" => "a.txt" })]
          ),
          Pocketrb::Providers::Message.tool_result(tool_call_id: "toolu_1", name: "read_file", content: "file body")
        ]

        provider.chat(messages: history, tools: tools)

        expect(WebMock).to(have_requested(:post, endpoint).once.with do |req|
          sent = JSON.parse(req.body)["messages"]
          sent.map { |m| m["role"] } == %w[user assistant user] &&
            sent[1]["content"].include?({ "type" => "text", "text" => "Reading it." }) &&
            sent[1]["content"].any? { |c| c["type"] == "tool_use" && c["id"] == "toolu_1" && c["input"] == { "path" => "a.txt" } } &&
            sent[2]["content"].any? { |c| c["type"] == "tool_result" && c["tool_use_id"] == "toolu_1" && c["content"].to_s.include?("file body") }
        end)
      end
    end
  end

  describe "#chat_stream" do
    let(:sse_body) do
      [
        { type: "message_start", message: { id: "msg_3", type: "message", role: "assistant", model: "claude-sonnet-5-5", content: [], usage: { input_tokens: 10, output_tokens: 0 } } },
        { type: "content_block_start", index: 0, content_block: { type: "text", text: "" } },
        { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: "Hi " } },
        { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: "there!" } },
        { type: "content_block_stop", index: 0 },
        { type: "message_delta", delta: { stop_reason: "end_turn" }, usage: { output_tokens: 5 } },
        { type: "message_stop" }
      ].map { |event| "event: #{event[:type]}\ndata: #{event.to_json}\n\n" }.join
    end

    before do
      stub_request(:post, endpoint).to_return(
        status: 200,
        body: sse_body,
        headers: { "Content-Type" => "text/event-stream" }
      )
    end

    it "yields text chunks and returns the full response" do
      chunks = []
      response = provider.chat_stream(messages: messages) { |chunk| chunks << chunk }

      expect(chunks).to eq(["Hi ", "there!"])
      expect(response).to have_attributes(content: "Hi there!", stop_reason: :end_turn)
      expect(WebMock).to(have_requested(:post, endpoint).with { |req| JSON.parse(req.body)["stream"] == true })
    end
  end
end
