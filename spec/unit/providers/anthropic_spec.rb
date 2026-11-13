# frozen_string_literal: true

require "spec_helper"

RSpec.describe Pocketrb::Providers::Anthropic do
  describe "authentication" do
    let(:url) { "https://api.anthropic.com/v1/messages" }
    let(:messages) { [Pocketrb::Providers::Message.user("Hello")] }

    before do
      stub_request(:post, url)
        .to_return(
          status: 200,
          body: {
            "content" => [{ "type" => "text", "text" => "Hi" }],
            "stop_reason" => "end_turn",
            "usage" => { "input_tokens" => 1, "output_tokens" => 1 },
            "model" => "claude-sonnet-5-5"
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    context "with API key" do
      before { ENV["ANTHROPIC_API_KEY"] = "test-api-key" }
      after { ENV.delete("ANTHROPIC_API_KEY") }

      it "creates provider successfully" do
        provider = described_class.new
        expect(provider.name).to eq(:anthropic)
      end

      it "sends the API key in the x-api-key header" do
        described_class.new.chat(messages: messages)

        expect(WebMock).to(have_requested(:post, url)
          .with { |req| req.headers["X-Api-Key"] == "test-api-key" && !req.headers.key?("Authorization") })
      end
    end

    context "with API key via config" do
      it "sends the configured API key" do
        described_class.new(anthropic_api_key: "config-api-key").chat(messages: messages)

        expect(WebMock).to(have_requested(:post, url)
          .with { |req| req.headers["X-Api-Key"] == "config-api-key" })
      end
    end

    context "with only ANTHROPIC_OAUTH_TOKEN" do
      before do
        ENV.delete("ANTHROPIC_API_KEY")
        ENV["ANTHROPIC_OAUTH_TOKEN"] = "test-oauth-token"
      end

      after { ENV.delete("ANTHROPIC_OAUTH_TOKEN") }

      it "does not authenticate with the OAuth token" do
        expect { described_class.new }.to raise_error(
          Pocketrb::ConfigurationError,
          /ANTHROPIC_API_KEY is required/
        )
      end

      it "does not accept an OAuth token via config" do
        expect { described_class.new(anthropic_oauth_token: "config-oauth-token") }.to raise_error(
          Pocketrb::ConfigurationError,
          /ANTHROPIC_API_KEY is required/
        )
      end
    end

    context "without any credentials" do
      before { ENV.delete("ANTHROPIC_API_KEY") }

      it "raises ConfigurationError" do
        expect { described_class.new }.to raise_error(
          Pocketrb::ConfigurationError,
          "ANTHROPIC_API_KEY is required for Pocketrb::Providers::Anthropic"
        )
      end
    end
  end

  describe "#default_model" do
    before { ENV["ANTHROPIC_API_KEY"] = "test-key" }
    after { ENV.delete("ANTHROPIC_API_KEY") }

    it "returns claude-sonnet-5-5" do
      provider = described_class.new
      expect(provider.default_model).to eq("claude-sonnet-5-5")
    end
  end

  describe "#available_models" do
    before { ENV["ANTHROPIC_API_KEY"] = "test-key" }
    after { ENV.delete("ANTHROPIC_API_KEY") }

    it "returns all supported models" do
      provider = described_class.new
      expect(provider.available_models).to include(
        "claude-opus-5-5",
        "claude-sonnet-5-5",
        "claude-haiku-5-5"
      )
    end
  end

  describe "#context_window" do
    before { ENV["ANTHROPIC_API_KEY"] = "test-key" }
    after { ENV.delete("ANTHROPIC_API_KEY") }

    let(:provider) { described_class.new }

    it "returns the default model window" do
      expect(provider.context_window).to eq(1_000_000)
    end

    it "returns the window of a listed model" do
      expect(provider.context_window(model: "claude-haiku-5-5")).to eq(1_000_000)
    end

    it "falls back to the base window for an unlisted model" do
      expect(provider.context_window(model: "unknown-model")).to eq(200_000)
    end
  end

  describe "#chat request body" do
    let(:provider) { described_class.new }
    let(:messages) { [Pocketrb::Providers::Message.user("Hello")] }

    before do
      ENV["ANTHROPIC_API_KEY"] = "test-key"
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(
          status: 200,
          body: {
            "content" => [{ "type" => "text", "text" => "Hi" }],
            "stop_reason" => "end_turn",
            "usage" => { "input_tokens" => 1, "output_tokens" => 1 },
            "model" => "claude-sonnet-5-5"
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    after { ENV.delete("ANTHROPIC_API_KEY") }

    it "omits temperature for the default model" do
      provider.chat(messages: messages)

      expect(WebMock).to(have_requested(:post, "https://api.anthropic.com/v1/messages")
        .with { |req| !JSON.parse(req.body).key?("temperature") })
    end

    it "sends temperature for an unlisted model" do
      provider.chat(messages: messages, model: "claude-sonnet-4-6", temperature: 0.3)

      expect(WebMock).to(have_requested(:post, "https://api.anthropic.com/v1/messages")
        .with { |req| JSON.parse(req.body).key?("temperature") })
    end

    %w[
      claude-opus-4-8 claude-opus-4-7-20260416 claude-sonnet-5 claude-haiku-5-5 claude-fable-5-1 claude-mythos-preview
    ].each do |model|
      it "omits temperature for #{model}, which rejects it" do
        provider.chat(messages: messages, model: model)

        expect(WebMock).to(have_requested(:post, "https://api.anthropic.com/v1/messages")
          .with { |req| !JSON.parse(req.body).key?("temperature") })
      end
    end

    %w[
      claude-opus-4-6 claude-opus-4-5-20251101 claude-opus-4-20250514 claude-haiku-4-5-20251001 claude-3-7-sonnet-20250219
    ].each do |model|
      it "sends temperature for #{model}, which accepts it" do
        provider.chat(messages: messages, model: model)

        expect(WebMock).to(have_requested(:post, "https://api.anthropic.com/v1/messages")
          .with { |req| JSON.parse(req.body).key?("temperature") })
      end
    end
  end

  describe "#supports?" do
    before { ENV["ANTHROPIC_API_KEY"] = "test-key" }
    after { ENV.delete("ANTHROPIC_API_KEY") }

    it "supports tools" do
      provider = described_class.new
      expect(provider.supports?(:tools)).to be true
    end

    it "supports streaming" do
      provider = described_class.new
      expect(provider.supports?(:streaming)).to be true
    end

    it "supports thinking" do
      provider = described_class.new
      expect(provider.supports?(:thinking)).to be true
    end

    it "supports vision" do
      provider = described_class.new
      expect(provider.supports?(:vision)).to be true
    end
  end
end
