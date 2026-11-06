# frozen_string_literal: true

module Pocketrb
  module Providers
    # Provider using the RubyLLM gem for multi-model support. This is an alternative to direct API calls
    class RubyLLMProvider < Base
      # Provider name
      # @return [Symbol]
      def name
        :ruby_llm
      end

      # Default model
      # @return [String]
      def default_model
        "claude-sonnet-5-5"
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
        model ||= default_model
        chat_instance = build_chat(messages, tools, model, temperature, max_tokens, thinking)

        parse_ruby_llm_response(chat_instance.generate, model)
      end

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
        model ||= default_model
        chat_instance = build_chat(messages, tools, model, temperature, max_tokens, false)

        response = chat_instance.generate do |chunk|
          block&.call(chunk.content) if chunk.content && !chunk.content.empty?
        end

        parse_ruby_llm_response(response, model)
      end

      protected

      # Supported provider features
      # @return [Array<Symbol>]
      def supported_features
        %i[tools streaming]
      end

      # Validate provider configuration (delegated to RubyLLM)
      # @return [void]
      def validate_config!
        # RubyLLM handles API key validation internally
      end

      private

      # Check if the RubyLLM gem is loaded
      # @return [Boolean]
      def ruby_llm_available?
        defined?(RubyLLM)
      end

      # Ensure RubyLLM is loaded, attempting to require it if needed
      # @return [void]
      # @raise [ConfigurationError] if the gem is not installed
      def ensure_ruby_llm!
        return if ruby_llm_available?

        require "ruby_llm"
      rescue LoadError
        raise ConfigurationError, "ruby_llm gem is not installed. Add it to your Gemfile."
      end

      # RubyLLM context holding this provider's API keys, leaving the global RubyLLM config untouched
      # @return [RubyLLM::Context]
      def ruby_llm_context
        ensure_ruby_llm!

        @ruby_llm_context ||= RubyLLM.context do |c|
          c.anthropic_api_key = api_key(:anthropic_api_key) if api_key(:anthropic_api_key)
          c.openai_api_key = api_key(:openai_api_key) if api_key(:openai_api_key)
        end
      end

      # Build a RubyLLM chat loaded with the conversation, without sending a request
      # @param messages [Array<Message>] conversation messages
      # @param tools [Array<Hash>, nil] tool definitions
      # @param model [String] model name
      # @param temperature [Float] sampling temperature
      # @param max_tokens [Integer] maximum tokens to generate
      # @param thinking [Boolean] enable extended thinking
      # @return [RubyLLM::Chat] configured chat instance
      def build_chat(messages, tools, model, temperature, max_tokens, thinking)
        chat = ruby_llm_context.chat(model: model)
        chat.with_max_output_tokens(max_tokens)
        chat.with_temperature(temperature) unless thinking || chat.model.metadata[:temperature] == false
        chat.with_thinking if thinking
        tools&.each { |tool| chat.with_tools(build_ruby_llm_tool(tool)) }
        messages.each { |msg| add_message_to_chat(chat, msg) }
        chat
      end

      # Wrap a tool definition as a RubyLLM tool. Pocketrb runs tools itself, so it is never executed here
      # @param tool [Hash] tool definition with optional :function key
      # @return [Class<RubyLLM::Tool>] RubyLLM tool class with the definition's name and schema
      def build_ruby_llm_tool(tool)
        definition = tool[:function] || tool
        tool_name = definition[:name].to_s
        schema = definition[:parameters] || definition[:input_schema]

        Class.new(RubyLLM::Tool) do
          description definition[:description]
          parameters schema if schema
          define_singleton_method(:tool_name) { tool_name }
        end
      end

      # Add a message to the RubyLLM chat instance based on its role
      # @param chat [RubyLLM::Chat] RubyLLM chat instance
      # @param message [Message] conversation message dispatched by role (system, user, assistant, tool)
      # @return [void]
      def add_message_to_chat(chat, message)
        case message.role
        when Role::SYSTEM
          chat.with_instructions(message.content, append: true)
        when Role::USER
          text, attachments = split_user_content(chat, message.content)
          chat.add_message(role: :user, content: text, attachments: attachments)
        when Role::ASSISTANT
          chat.add_message(
            role: :assistant,
            content: message.content.to_s.empty? ? nil : message.content,
            tool_calls: build_ruby_llm_tool_calls(message.tool_calls)
          )
        when Role::TOOL
          chat.add_message(role: :tool, content: message.content.to_s, tool_call_id: message.tool_call_id)
        end
      end

      # Split user content into text and RubyLLM attachments. Media the model cannot read, or that is missing,
      # becomes placeholder text, as RubyLLM raises on it
      # @param chat [RubyLLM::Chat] chat whose model decides which images it accepts
      # @param content [String, Array<Hash>] text or content blocks with text and media
      # @return [Array(String, Array<RubyLLM::Attachment>)] text and attachments
      def split_user_content(chat, content)
        return [content, []] unless content.is_a?(Array)

        vision = chat.model.modalities.input.include?("image")
        texts = []
        attachments = []

        content.each do |block|
          next texts << block[:text] if block[:type] == "text"
          next unless block[:type] == "media"

          attachment = build_attachment(block[:media], vision)
          attachment.is_a?(String) ? texts << attachment : attachments << attachment
        end

        [texts.join("\n"), attachments]
      end

      # Convert a media item to a RubyLLM attachment, or to placeholder text when it cannot be sent
      # @param media [Bus::Media, nil] media with a file path or base64 data
      # @param vision [Boolean] whether the model accepts image input
      # @return [RubyLLM::Attachment, String] attachment or placeholder text
      def build_attachment(media, vision)
        return "[unsupported media]" unless media
        unless vision && media.image? && Media::Processor::VISION_IMAGE_TYPES.include?(media.mime_type)
          return "[Attached: #{media.filename} (#{media.mime_type})]"
        end

        filename = media.filename || File.basename(media.path.to_s)
        if media.data
          RubyLLM::Attachment.new(StringIO.new(Base64.decode64(media.data)), filename: filename)
        elsif media.path && File.exist?(media.path)
          RubyLLM::Attachment.new(media.path, filename: filename)
        else
          "[Image not available]"
        end
      end

      # Convert pocketrb tool calls to RubyLLM tool calls keyed by ID
      # @param tool_calls [Array<ToolCall>, nil] tool calls made by the assistant
      # @return [Hash{String => RubyLLM::ToolCall}, nil] RubyLLM tool calls
      def build_ruby_llm_tool_calls(tool_calls)
        return if tool_calls.nil? || tool_calls.empty?

        tool_calls.to_h do |tc|
          [tc.id, RubyLLM::ToolCall.new(id: tc.id, name: tc.name, arguments: tc.arguments)]
        end
      end

      # Parse a RubyLLM response into an LLMResponse
      # @param response [RubyLLM::Message] RubyLLM assistant message
      # @param model [String] model name used
      # @return [LLMResponse] structured response
      def parse_ruby_llm_response(response, model)
        tool_calls = (response.tool_calls || {}).values.map do |tc|
          ToolCall.new(id: tc.id, name: tc.name, arguments: tc.arguments)
        end

        LLMResponse.new(
          content: response.content,
          tool_calls: tool_calls,
          usage: Usage.new(
            input_tokens: response.tokens.input || 0,
            output_tokens: response.tokens.output || 0,
            cache_read: response.tokens.cache_read,
            cache_write: response.tokens.cache_write
          ),
          stop_reason: stop_reason(response),
          model: model,
          thinking: response.thinking&.text
        )
      end

      # Map a RubyLLM finish reason to an LLMResponse stop reason
      # @param response [RubyLLM::Message] RubyLLM assistant message
      # @return [Symbol] :tool_use, :max_tokens or :end_turn
      def stop_reason(response)
        return :tool_use if response.tool_call?
        return :max_tokens if response.max_tokens?

        :end_turn
      end
    end
  end
end
