# frozen_string_literal: true

require "spec_helper"

RSpec.describe Pocketrb::Providers::Anthropic do
  describe "authentication" do
    context "with API key" do
      before do
        ENV["ANTHROPIC_API_KEY"] = "test-api-key"
        ENV.delete("ANTHROPIC_OAUTH_TOKEN")
      end

      after do
        ENV.delete("ANTHROPIC_API_KEY")
      end

      it "creates provider successfully" do
        provider = described_class.new
        expect(provider.name).to eq(:anthropic)
      end

      it "uses x-api-key header" do
        provider = described_class.new
        expect(provider.send(:using_oauth?)).to be false
      end
    end

    context "with OAuth token (Max subscription)" do
      before do
        ENV.delete("ANTHROPIC_API_KEY")
        ENV["ANTHROPIC_OAUTH_TOKEN"] = "test-oauth-token"
      end

      after do
        ENV.delete("ANTHROPIC_OAUTH_TOKEN")
      end

      it "creates provider successfully" do
        provider = described_class.new
        expect(provider.name).to eq(:anthropic)
      end

      it "uses OAuth authentication" do
        provider = described_class.new
        expect(provider.send(:using_oauth?)).to be true
      end

      it "returns the OAuth token" do
        provider = described_class.new
        expect(provider.send(:oauth_token)).to eq("test-oauth-token")
      end
    end

    context "with both API key and OAuth token" do
      before do
        ENV["ANTHROPIC_API_KEY"] = "test-api-key"
        ENV["ANTHROPIC_OAUTH_TOKEN"] = "test-oauth-token"
      end

      after do
        ENV.delete("ANTHROPIC_API_KEY")
        ENV.delete("ANTHROPIC_OAUTH_TOKEN")
      end

      it "prefers OAuth token" do
        provider = described_class.new
        expect(provider.send(:using_oauth?)).to be true
      end
    end

    context "with config hash" do
      it "accepts OAuth token via config" do
        provider = described_class.new(anthropic_oauth_token: "config-oauth-token")
        expect(provider.send(:oauth_token)).to eq("config-oauth-token")
        expect(provider.send(:using_oauth?)).to be true
      end

      it "accepts API key via config" do
        provider = described_class.new(anthropic_api_key: "config-api-key")
        expect(provider.send(:using_oauth?)).to be false
      end
    end

    context "without any credentials" do
      before do
        ENV.delete("ANTHROPIC_API_KEY")
        ENV.delete("ANTHROPIC_OAUTH_TOKEN")
      end

      it "raises ConfigurationError" do
        expect { described_class.new }.to raise_error(
          Pocketrb::ConfigurationError,
          /Either ANTHROPIC_OAUTH_TOKEN or ANTHROPIC_API_KEY is required/
        )
      end
    end
  end

  describe "#default_model" do
    before { ENV["ANTHROPIC_API_KEY"] = "test-key" }
    after { ENV.delete("ANTHROPIC_API_KEY") }

    it "returns claude-sonnet-4" do
      provider = described_class.new
      expect(provider.default_model).to eq("claude-sonnet-4-20250514")
    end
  end

  describe "#available_models" do
    before { ENV["ANTHROPIC_API_KEY"] = "test-key" }
    after { ENV.delete("ANTHROPIC_API_KEY") }

    it "returns all supported models" do
      provider = described_class.new
      expect(provider.available_models).to include(
        "claude-opus-4-20250514",
        "claude-sonnet-4-20250514",
        "claude-3-5-haiku-20241022"
      )
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
