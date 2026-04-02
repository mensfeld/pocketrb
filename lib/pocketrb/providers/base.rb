# frozen_string_literal: true

module Pocketrb
  module Providers
    # Base class for LLM providers
    class Base
      attr_reader :config

      # Initialize provider
      # @param config [Hash] Provider configuration options (defaults to empty hash)
      def initialize(config = {})
        @config = config
        validate_config!
      end

      # Send a chat completion request
      # @param messages [Array<Message>] Conversation history
      # @param tools [Array<Hash>, nil] Tool definitions
      # @param model [String, nil] Model to use (defaults to provider default)
      # @param temperature [Float] Sampling temperature
      # @param max_tokens [Integer] Maximum tokens to generate
      # @param thinking [Boolean] Enable extended thinking (Claude only)
      # @return [LLMResponse]
      def chat(messages:, tools: nil, model: nil, temperature: 0.7, max_tokens: 4096, thinking: false)
        raise NotImplementedError, "#{self.class}#chat must be implemented"
      end

      # Stream a chat completion request
      # @param messages [Array<Message>] Conversation history
      # @param tools [Array<Hash>, nil] Tool definitions
      # @param model [String, nil] Model to use (defaults to provider default)
      # @param temperature [Float] Sampling temperature
      # @param max_tokens [Integer] Maximum tokens to generate
      # @param block [Proc] Block to receive streaming chunks
      # @yieldparam chunk [String] Text chunk from streaming response
      # @return [LLMResponse] Final complete response
      def chat_stream(messages:, tools: nil, model: nil, temperature: 0.7, max_tokens: 4096, &block)
        raise NotImplementedError, "#{self.class}#chat_stream must be implemented"
      end

      # Get the default model for this provider
      # @return [String]
      def default_model
        raise NotImplementedError, "#{self.class}#default_model must be implemented"
      end

      # List available models
      # @return [Array<String>]
      def available_models
        raise NotImplementedError, "#{self.class}#available_models must be implemented"
      end

      # Provider name
      # @return [Symbol]
      def name
        raise NotImplementedError, "#{self.class}#name must be implemented"
      end

      # Get the context window size for a model
      # @param model [String, nil] Model name (defaults to default_model)
      # @return [Integer] Context window size in tokens
      def context_window(model: nil)
        200_000
      end

      # Check if provider supports a feature
      # @param feature [Symbol] :tools, :streaming, :thinking, :vision
      # @return [Boolean]
      def supports?(feature)
        supported_features.include?(feature)
      end

      protected

      # Supported provider features
      # @return [Array<Symbol>]
      def supported_features
        %i[tools streaming]
      end

      # Validate provider configuration
      # @return [void]
      def validate_config!
        # Override in subclasses to validate required config
      end

      # Raise error if API key is missing from config and environment
      # @param key_name [Symbol] configuration key name
      # @return [void]
      # @raise [ConfigurationError] if API key is not found
      def require_api_key!(key_name)
        return if @config[key_name] || ENV[key_name.to_s.upcase]

        raise ConfigurationError, "#{key_name} is required for #{self.class.name}"
      end

      # Fetch API key from config or environment
      # @param key_name [Symbol] configuration key name
      # @return [String, nil] API key value
      def api_key(key_name)
        @config[key_name] || ENV.fetch(key_name.to_s.upcase, nil)
      end

      # Convert internal message format to provider-specific format
      # @param messages [Array<Message>] conversation history to convert for the provider API
      # @return [Array<Hash>] provider-formatted messages
      def format_messages(messages)
        messages.map { |msg| format_message(msg) }
      end

      # Format a single message for the provider
      # @param message [Message] conversation message with role, content, and optional tool data
      # @return [Hash] provider-formatted message
      def format_message(message)
        raise NotImplementedError
      end

      # Convert provider response to internal format
      # @param response [Hash] raw provider response
      # @return [LLMResponse] parsed response
      def parse_response(response)
        raise NotImplementedError
      end

      # Convert tool definitions to provider-specific format
      # @param tools [Array<Hash>] tool definitions
      # @return [Array<Hash>] provider-formatted tools
      def format_tools(tools)
        tools
      end
    end
  end
end
