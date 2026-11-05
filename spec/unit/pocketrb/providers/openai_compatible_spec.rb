# frozen_string_literal: true

RSpec.describe Pocketrb::Providers::OpenAICompatible do
  let(:endpoint) { "http://localhost:8000/v1/chat/completions" }
  let(:config) { { openai_compatible_base_url: "http://localhost:8000/v1", model: "llama-3.1-8b-instruct" } }
  let(:provider) { described_class.new(config) }
  let(:messages) { [Pocketrb::Providers::Message.user("Hello")] }

  let(:mock_response) do
    {
      "choices" => [
        {
          "message" => { "role" => "assistant", "content" => "Hi there!" },
          "finish_reason" => "stop"
        }
      ],
      "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5 },
      "model" => "llama-3.1-8b-instruct"
    }
  end

  before do
    stub_request(:post, endpoint).to_return(status: 200, body: mock_response.to_json)
  end

  describe "#name" do
    it "returns openai_compatible" do
      expect(provider.name).to eq(:openai_compatible)
    end
  end

  describe "#default_model" do
    it "returns the configured model" do
      expect(provider.default_model).to eq("llama-3.1-8b-instruct")
    end
  end

  describe "#available_models" do
    it "returns the configured model" do
      expect(provider.available_models).to eq(["llama-3.1-8b-instruct"])
    end
  end

  describe "configuration" do
    context "without base URL" do
      it "raises ConfigurationError" do
        expect do
          described_class.new({})
        end.to raise_error(Pocketrb::ConfigurationError, /openai_compatible_base_url/)
      end
    end

    context "with empty base URL" do
      it "raises ConfigurationError" do
        expect do
          described_class.new(openai_compatible_base_url: "")
        end.to raise_error(Pocketrb::ConfigurationError, /openai_compatible_base_url is required/)
      end
    end

    context "with base URL without scheme" do
      it "raises ConfigurationError" do
        expect do
          described_class.new(openai_compatible_base_url: "localhost:8000/v1")
        end.to raise_error(Pocketrb::ConfigurationError, /must be an http\(s\) URL/)
      end
    end

    context "with base URL without host" do
      it "raises ConfigurationError" do
        expect do
          described_class.new(openai_compatible_base_url: "http://")
        end.to raise_error(Pocketrb::ConfigurationError, /must be an http\(s\) URL/)
      end
    end

    context "with base URL from environment" do
      around do |example|
        ENV["OPENAI_COMPATIBLE_BASE_URL"] = "http://127.0.0.1:1234/v1"
        example.run
      ensure
        ENV.delete("OPENAI_COMPATIBLE_BASE_URL")
      end

      it "uses it" do
        stub_request(:post, "http://127.0.0.1:1234/v1/chat/completions")
          .to_return(status: 200, body: mock_response.to_json)

        described_class.new({}).chat(messages: messages)

        expect(WebMock).to have_requested(:post, "http://127.0.0.1:1234/v1/chat/completions")
      end
    end
  end

  describe "#chat" do
    it "sends the request to the configured base URL" do
      response = provider.chat(messages: messages)

      expect(response.content).to eq("Hi there!")
      expect(response.usage.input_tokens).to eq(10)
      expect(WebMock).to have_requested(:post, endpoint)
    end

    it "keeps a trailing slash in the base URL working" do
      described_class.new(config.merge(openai_compatible_base_url: "http://localhost:8000/v1/")).chat(messages: messages)

      expect(WebMock).to have_requested(:post, endpoint)
    end

    it "uses the configured model by default" do
      provider.chat(messages: messages)

      expect(WebMock).to(have_requested(:post, endpoint)
        .with { |req| JSON.parse(req.body)["model"] == "llama-3.1-8b-instruct" })
    end

    it "uses custom model when specified" do
      provider.chat(messages: messages, model: "qwen2.5-coder")

      expect(WebMock).to(have_requested(:post, endpoint)
        .with { |req| JSON.parse(req.body)["model"] == "qwen2.5-coder" })
    end

    it "does not send OpenRouter headers" do
      provider.chat(messages: messages)

      expect(WebMock).to(have_requested(:post, endpoint)
        .with { |req| !req.headers.key?("Http-Referer") && !req.headers.key?("X-Title") })
    end

    context "without API key" do
      it "sends no authorization header" do
        provider.chat(messages: messages)

        expect(WebMock).to(have_requested(:post, endpoint)
          .with { |req| !req.headers.key?("Authorization") })
      end
    end

    context "with API key" do
      let(:config) { super().merge(openai_compatible_api_key: "local-key") }

      it "sets authorization header" do
        provider.chat(messages: messages)

        expect(WebMock).to have_requested(:post, endpoint)
          .with(headers: { "Authorization" => "Bearer local-key" })
      end
    end

    context "with API key from environment" do
      around do |example|
        ENV["OPENAI_COMPATIBLE_API_KEY"] = "env-key"
        example.run
      ensure
        ENV.delete("OPENAI_COMPATIBLE_API_KEY")
      end

      it "sets authorization header" do
        provider.chat(messages: messages)

        expect(WebMock).to have_requested(:post, endpoint)
          .with(headers: { "Authorization" => "Bearer env-key" })
      end
    end

    context "with API error" do
      before do
        stub_request(:post, endpoint)
          .to_return(status: 404, body: { "error" => "model not found" }.to_json)
      end

      it "raises ProviderError" do
        expect do
          provider.chat(messages: messages)
        end.to raise_error(Pocketrb::ProviderError, /OpenAI-compatible API error: model not found/)
      end
    end
  end

  describe "#chat_stream" do
    before do
      events = [
        { "choices" => [{ "delta" => { "content" => "Hi" } }] },
        { "choices" => [{ "delta" => { "content" => " there!" } }] }
      ].map { |data| "data: #{data.to_json}\n\n" }

      stub_request(:post, endpoint).to_return(status: 200, body: "#{events.join}data: [DONE]\n\n")
    end

    it "streams from the configured base URL" do
      chunks = []

      response = provider.chat_stream(messages: messages) { |chunk| chunks << chunk }

      expect(chunks).to eq(["Hi", " there!"])
      expect(response.content).to eq("Hi there!")
      expect(WebMock).to(have_requested(:post, endpoint)
        .with { |req| JSON.parse(req.body)["stream"] == true })
    end
  end
end
