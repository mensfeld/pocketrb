# frozen_string_literal: true

# Pocketrb: Ruby AI agent with multi-LLM support and advanced planning capabilities
module Pocketrb
  # LLM provider implementations
  module Providers
    # Provider using the RubyLLM gem for multi-model support
    # This is an alternative to direct API calls
    class RubyLLMProvider < Base
      # Provider name
      # @return [Symbol]
      def name
        :ruby_llm
      end

      # Default model
      # @return [String]
      def default_model
        "claude-sonnet-4-20250514"
      end

      # Available models
      # @return [Array<String>]
      def available_models
        return [] unless ruby_llm_available?

        RubyLLM.models.map(&:id)
      end

      # Send chat completion request
      # @param messages [Array<Message>] Conversation messages
      # @param tools [Array<Hash>, nil] Tool definitions
      # @param model [String, nil] Model name
      # @param temperature [Float] Sampling temperature
      # @param max_tokens [Integer] Maximum tokens to generate
      # @param thinking [Boolean] Enable extended thinking
      # @return [LLMResponse] Parsed response
      def chat(messages:, tools: nil, model: nil, temperature: 0.7, max_tokens: 4096, thinking: false)
        ensure_ruby_llm!

        model ||= default_model
        chat_instance = RubyLLM.chat(model: model)

        # Add tools if provided
        tools&.each do |tool|
          chat_instance.with_tool(build_ruby_llm_tool(tool))
        end

        # Configure and send
        messages.each { |msg| add_message_to_chat(chat_instance, msg) }

        response = chat_instance.complete

        parse_ruby_llm_response(response, model)
      end

      # Send streaming chat completion request
      # Send streaming chat completion request
      # @param messages [Array<Message>] Conversation messages
      # @param tools [Array<Hash>, nil] Tool definitions
      # @param model [String, nil] Model name
      # @param temperature [Float] Sampling temperature
      # @param max_tokens [Integer] Maximum tokens to generate
      # @param block [Proc] Block to receive streaming chunks
      # @yieldparam chunk [String] Streamed text chunk
      # @return [LLMResponse] Final response
      def chat_stream(messages:, tools: nil, model: nil, temperature: 0.7, max_tokens: 4096, &block)
        ensure_ruby_llm!

        model ||= default_model
        chat_instance = RubyLLM.chat(model: model)

        tools&.each do |tool|
          chat_instance.with_tool(build_ruby_llm_tool(tool))
        end

        messages.each { |msg| add_message_to_chat(chat_instance, msg) }

        accumulated = ""
        response = chat_instance.stream do |chunk|
          accumulated << chunk.content if chunk.content
          block&.call(chunk.content)
        end

        parse_ruby_llm_response(response, model)
      end

      protected

      def supported_features
        %i[tools streaming]
      end

      def validate_config!
        # RubyLLM handles API key validation internally
      end

      private

      def ruby_llm_available?
        defined?(RubyLLM)
      end

      def ensure_ruby_llm!
        return if ruby_llm_available?

        begin
          require "ruby_llm"
          configure_ruby_llm
        rescue LoadError
          raise ConfigurationError, "ruby_llm gem is not installed. Add it to your Gemfile."
        end
      end

      def configure_ruby_llm
        RubyLLM.configure do |c|
          c.anthropic_api_key = api_key(:anthropic_api_key) if api_key(:anthropic_api_key)
          c.openai_api_key = api_key(:openai_api_key) if api_key(:openai_api_key)
        end
      end

      def build_ruby_llm_tool(tool)
        tool[:function] || tool
        # RubyLLM uses a different tool format - this would need adaptation
        # based on actual RubyLLM API
      end

      def add_message_to_chat(chat, message)
        case message.role
        when Role::SYSTEM
          chat.with_system_prompt(message.content)
        when Role::USER
          chat.ask(message.content, stream: false)
        when Role::ASSISTANT
          # RubyLLM manages assistant messages internally
        when Role::TOOL
          # Tool results handled differently in RubyLLM
        end
      end

      def parse_ruby_llm_response(response, model)
        tool_calls = (response.tool_calls || []).map do |tc|
          ToolCall.new(
            id: tc.id,
            name: tc.name,
            arguments: tc.arguments
          )
        end

        LLMResponse.new(
          content: response.content,
          tool_calls: tool_calls,
          usage: Usage.new(
            input_tokens: response.input_tokens || 0,
            output_tokens: response.output_tokens || 0
          ),
          model: model
        )
      end
    end
  end
end
