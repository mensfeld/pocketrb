# frozen_string_literal: true

module Pocketrb
  module Providers
    # Base class for LLM providers
    class Base
      attr_reader :config

      def initialize(config = {})
        @config = config
        validate_config!
      end

      # Send a chat completion request
      # @param messages [Array<Message>] Conversation history
      # @param tools [Array<Hash>|nil] Tool definitions
      # @param model [String|nil] Model to use (defaults to provider default)
      # @param temperature [Float] Sampling temperature
      # @param max_tokens [Integer] Maximum tokens to generate
      # @param thinking [Boolean] Enable extended thinking (Claude only)
      # @return [LLMResponse]
      def chat(messages:, tools: nil, model: nil, temperature: 0.7, max_tokens: 4096, thinking: false)
        raise NotImplementedError, "#{self.class}#chat must be implemented"
      end

      # Stream a chat completion request
      # @yield [String|ToolCall] Chunks of content or tool calls
      # @return [LLMResponse]
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

      # Check if provider supports a feature
      # @param feature [Symbol] :tools, :streaming, :thinking, :vision
      # @return [Boolean]
      def supports?(feature)
        supported_features.include?(feature)
      end

      protected

      def supported_features
        %i[tools streaming]
      end

      def validate_config!
        # Override in subclasses to validate required config
      end

      def require_api_key!(key_name)
        return if @config[key_name] || ENV[key_name.to_s.upcase]

        raise ConfigurationError, "#{key_name} is required for #{self.class.name}"
      end

      def api_key(key_name)
        @config[key_name] || ENV[key_name.to_s.upcase]
      end

      # Convert internal message format to provider-specific format
      def format_messages(messages)
        messages.map { |msg| format_message(msg) }
      end

      def format_message(message)
        raise NotImplementedError
      end

      # Convert provider response to internal format
      def parse_response(response)
        raise NotImplementedError
      end

      # Convert tool definitions to provider-specific format
      def format_tools(tools)
        tools
      end
    end
  end
end
