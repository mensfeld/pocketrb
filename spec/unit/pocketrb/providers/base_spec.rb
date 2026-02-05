# frozen_string_literal: true

# Test subclass for testing Base functionality
class TestProvider < Pocketrb::Providers::Base
  attr_reader :validated

  def name
    :test
  end

  def default_model
    "test-model-1"
  end

  def available_models
    %w[test-model-1 test-model-2]
  end

  def chat(messages:, tools: nil, model: nil, temperature: 0.7, max_tokens: 4096, thinking: false)
    Pocketrb::Providers::LLMResponse.new(
      content: "Test response",
      model: model || default_model
    )
  end

  def chat_stream(messages:, tools: nil, model: nil, temperature: 0.7, max_tokens: 4096, &block)
    block&.call("Test")
    chat(messages: messages, model: model)
  end

  protected

  def validate_config!
    @validated = true
    super
  end

  def format_message(message)
    { role: message.role, content: message.content }
  end

  def parse_response(response)
    response
  end
end

# Test subclass with custom supported features
class AdvancedProvider < Pocketrb::Providers::Base
  def name
    :advanced
  end

  def default_model
    "advanced-model"
  end

  def available_models
    ["advanced-model"]
  end

  def chat(messages:, **_kwargs)
    Pocketrb::Providers::LLMResponse.new(content: "Response", model: default_model)
  end

  protected

  def supported_features
    %i[tools streaming vision thinking]
  end

  def format_message(message)
    message
  end

  def parse_response(response)
    response
  end
end

RSpec.describe Pocketrb::Providers::Base do
  let(:config) { {} }
  let(:provider) { TestProvider.new(config) }

  describe "#initialize" do
    it "stores config" do
      config = { api_key: "test123" }
      provider = TestProvider.new(config)

      expect(provider.config).to eq(config)
    end

    it "calls validate_config!" do
      provider = TestProvider.new({})

      expect(provider.validated).to be true
    end

    it "accepts empty config" do
      expect { TestProvider.new }.not_to raise_error
    end
  end

  describe "#name" do
    it "raises NotImplementedError for base class" do
      base = described_class.new

      expect { base.name }.to raise_error(NotImplementedError)
    end

    it "can be implemented by subclass" do
      expect(provider.name).to eq(:test)
    end
  end

  describe "#default_model" do
    it "raises NotImplementedError for base class" do
      base = described_class.new

      expect { base.default_model }.to raise_error(NotImplementedError)
    end

    it "can be implemented by subclass" do
      expect(provider.default_model).to eq("test-model-1")
    end
  end

  describe "#available_models" do
    it "raises NotImplementedError for base class" do
      base = described_class.new

      expect { base.available_models }.to raise_error(NotImplementedError)
    end

    it "can be implemented by subclass" do
      expect(provider.available_models).to include("test-model-1", "test-model-2")
    end
  end

  describe "#chat" do
    it "raises NotImplementedError for base class" do
      base = described_class.new

      expect { base.chat(messages: []) }.to raise_error(NotImplementedError)
    end

    it "can be implemented by subclass" do
      messages = [Pocketrb::Providers::Message.user("Hello")]
      response = provider.chat(messages: messages)

      expect(response).to be_a(Pocketrb::Providers::LLMResponse)
      expect(response.content).to eq("Test response")
    end
  end

  describe "#chat_stream" do
    it "raises NotImplementedError for base class" do
      base = described_class.new

      expect { base.chat_stream(messages: []) }.to raise_error(NotImplementedError)
    end

    it "can be implemented by subclass" do
      messages = [Pocketrb::Providers::Message.user("Hello")]
      chunks = []

      response = provider.chat_stream(messages: messages) do |chunk|
        chunks << chunk
      end

      expect(chunks).to include("Test")
      expect(response).to be_a(Pocketrb::Providers::LLMResponse)
    end
  end

  describe "#supports?" do
    it "returns true for supported features" do
      expect(provider.supports?(:tools)).to be true
      expect(provider.supports?(:streaming)).to be true
    end

    it "returns false for unsupported features" do
      expect(provider.supports?(:vision)).to be false
      expect(provider.supports?(:thinking)).to be false
    end

    it "can be customized by subclass" do
      advanced = AdvancedProvider.new

      expect(advanced.supports?(:vision)).to be true
      expect(advanced.supports?(:thinking)).to be true
    end
  end

  describe "#require_api_key!" do
    context "when key exists in config" do
      let(:config) { { api_key: "test123" } }

      it "does not raise error" do
        expect { provider.send(:require_api_key!, :api_key) }.not_to raise_error
      end
    end

    context "when key exists in ENV" do
      before do
        allow(ENV).to receive(:[]).with("API_KEY").and_return("env_key")
      end

      it "does not raise error" do
        expect { provider.send(:require_api_key!, :api_key) }.not_to raise_error
      end
    end

    context "when key missing from both" do
      it "raises ConfigurationError" do
        expect do
          provider.send(:require_api_key!, :api_key)
        end.to raise_error(Pocketrb::ConfigurationError, /api_key is required/)
      end

      it "includes provider class name in error" do
        expect do
          provider.send(:require_api_key!, :api_key)
        end.to raise_error(Pocketrb::ConfigurationError, /TestProvider/)
      end
    end
  end

  describe "#api_key" do
    context "when key in config" do
      let(:config) { { api_key: "config_key" } }

      it "returns config value" do
        expect(provider.send(:api_key, :api_key)).to eq("config_key")
      end

      it "prefers config over ENV" do
        allow(ENV).to receive(:fetch).with("API_KEY", nil).and_return("env_key")

        expect(provider.send(:api_key, :api_key)).to eq("config_key")
      end
    end

    context "when key only in ENV" do
      before do
        allow(ENV).to receive(:fetch).with("API_KEY", nil).and_return("env_key")
      end

      it "returns ENV value" do
        expect(provider.send(:api_key, :api_key)).to eq("env_key")
      end
    end

    context "when key missing from both" do
      before do
        allow(ENV).to receive(:fetch).with("API_KEY", nil).and_return(nil)
      end

      it "returns nil" do
        expect(provider.send(:api_key, :api_key)).to be_nil
      end
    end
  end

  describe "#format_messages" do
    it "calls format_message for each message" do
      messages = [
        Pocketrb::Providers::Message.user("Hello"),
        Pocketrb::Providers::Message.assistant("Hi")
      ]

      formatted = provider.send(:format_messages, messages)

      expect(formatted.length).to eq(2)
      expect(formatted[0][:role]).to eq("user")
      expect(formatted[1][:role]).to eq("assistant")
    end

    it "raises NotImplementedError for base class" do
      base = described_class.new
      message = Pocketrb::Providers::Message.user("Test")

      expect do
        base.send(:format_message, message)
      end.to raise_error(NotImplementedError)
    end
  end

  describe "#parse_response" do
    it "raises NotImplementedError for base class" do
      base = described_class.new

      expect { base.send(:parse_response, {}) }.to raise_error(NotImplementedError)
    end
  end

  describe "#format_tools" do
    it "returns tools unchanged by default" do
      tools = [{ name: "test", description: "Test tool" }]

      formatted = provider.send(:format_tools, tools)

      expect(formatted).to eq(tools)
    end
  end

  describe "#supported_features" do
    it "includes tools and streaming by default" do
      features = provider.send(:supported_features)

      expect(features).to include(:tools, :streaming)
    end

    it "can be overridden by subclass" do
      advanced = AdvancedProvider.new
      features = advanced.send(:supported_features)

      expect(features).to include(:vision, :thinking)
    end
  end
end
