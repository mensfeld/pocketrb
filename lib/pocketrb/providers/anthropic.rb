# frozen_string_literal: true

require "faraday"
require "json"

module Pocketrb
  module Providers
    # Direct Anthropic Claude API provider
    # Supports extended thinking and all Claude-specific features
    class Anthropic < Base
      # Anthropic API base URL
      API_URL = "https://api.anthropic.com/v1"
      # Anthropic API version header value
      API_VERSION = "2023-06-01"

      # Supported Claude models with context and output token limits
      MODELS = {
        "claude-opus-4-20250514" => { context: 200_000, output: 32_000 },
        "claude-sonnet-4-20250514" => { context: 200_000, output: 64_000 },
        "claude-3-5-haiku-20241022" => { context: 200_000, output: 8192 }
      }.freeze

      # Provider name
      # @return [Symbol]
      def name
        :anthropic
      end

      # Get the context window size for a model
      # @param model [String, nil] Model name (defaults to default_model)
      # @return [Integer] Context window size in tokens
      def context_window(model: nil)
        model ||= default_model
        MODELS.dig(model, :context) || super
      end

      # Default model to use
      # @return [String]
      def default_model
        "claude-sonnet-4-20250514"
      end

      # List of available models
      # @return [Array<String>]
      def available_models
        MODELS.keys
      end

      # Send chat completion request
      # @param messages [Array<Message>] Conversation messages
      # @param tools [Array<Hash>, nil] Tool definitions
      # @param model [String, nil] Model name (defaults to default_model)
      # @param temperature [Float] Sampling temperature (0.0-1.0)
      # @param max_tokens [Integer] Maximum tokens to generate
      # @param thinking [Boolean] Whether to enable extended thinking mode
      # @return [LLMResponse] Parsed response with content and tool calls
      def chat(messages:, tools: nil, model: nil, temperature: 0.7, max_tokens: 4096, thinking: false)
        model ||= default_model
        body = build_request_body(messages, tools, model, temperature, max_tokens, thinking)

        response = client.post("/v1/messages") do |req|
          req.body = body.to_json
        end

        handle_response(response)
      end

      # Send streaming chat completion request
      # @param messages [Array<Message>] Conversation messages
      # @param tools [Array<Hash>, nil] Tool definitions
      # @param model [String, nil] Model name (defaults to default_model)
      # @param temperature [Float] Sampling temperature (0.0-1.0)
      # @param max_tokens [Integer] Maximum tokens to generate
      # @param block [Proc] Block to receive streaming chunks
      # @yieldparam chunk [Hash] Streamed response chunk
      # @return [LLMResponse] Final response with accumulated content
      def chat_stream(messages:, tools: nil, model: nil, temperature: 0.7, max_tokens: 4096, &block)
        model ||= default_model
        body = build_request_body(messages, tools, model, temperature, max_tokens, false)
        body[:stream] = true

        accumulated_content = ""
        accumulated_tool_calls = []
        usage = nil

        client.post("/v1/messages") do |req|
          req.body = body.to_json
          req.options.on_data = proc do |chunk, _|
            process_stream_chunk(chunk, accumulated_content, accumulated_tool_calls, &block)
          end
        end

        LLMResponse.new(
          content: accumulated_content,
          tool_calls: accumulated_tool_calls,
          usage: usage,
          model: model
        )
      end

      protected

      # Supported provider features
      # @return [Array<Symbol>]
      def supported_features
        %i[tools streaming thinking vision]
      end

      # Validate that required API credentials are present
      # @return [void]
      # @raise [ConfigurationError] if no credentials are configured
      def validate_config!
        return if oauth_token
        return if api_key(:anthropic_api_key)

        raise ConfigurationError,
              "Either ANTHROPIC_OAUTH_TOKEN or ANTHROPIC_API_KEY is required for #{self.class.name}"
      end

      private

      # Check for OAuth token (Max subscription via `claude setup-token`)
      # @return [String, nil] OAuth token if configured
      def oauth_token
        @config[:anthropic_oauth_token] || ENV.fetch("ANTHROPIC_OAUTH_TOKEN", nil)
      end

      # Whether OAuth authentication is being used
      # @return [Boolean]
      def using_oauth?
        !oauth_token.nil?
      end

      # Build Faraday HTTP client with appropriate authentication headers
      # @return [Faraday::Connection]
      def client
        @client ||= Faraday.new(url: API_URL) do |f|
          f.headers["Content-Type"] = "application/json"
          f.headers["anthropic-version"] = API_VERSION

          if using_oauth?
            # OAuth authentication for Max subscription
            # Token generated via: claude setup-token
            f.headers["Authorization"] = "Bearer #{oauth_token}"
            f.headers["anthropic-beta"] = "oauth-2025-04-20"
          else
            # Standard API key authentication
            f.headers["x-api-key"] = api_key(:anthropic_api_key)
          end

          f.adapter Faraday.default_adapter
        end
      end

      # Build the API request body for Anthropic messages endpoint
      # @param messages [Array<Message>] conversation messages
      # @param tools [Array<Hash>, nil] tool definitions
      # @param model [String] model name
      # @param temperature [Float] sampling temperature
      # @param max_tokens [Integer] maximum tokens to generate
      # @param thinking [Boolean] whether to enable extended thinking
      # @return [Hash] request body
      def build_request_body(messages, tools, model, temperature, max_tokens, thinking)
        system_message = extract_system_message(messages)
        conversation = format_messages(messages.reject { |m| m.role == Role::SYSTEM })

        body = {
          model: model,
          messages: conversation,
          max_tokens: max_tokens
        }

        body[:system] = system_message if system_message
        body[:temperature] = temperature unless thinking
        body[:tools] = format_tools(tools) if tools&.any?

        body[:thinking] = { type: "enabled", budget_tokens: [max_tokens / 2, 10_000].min } if thinking

        body
      end

      # Extract system message content from the message list
      # @param messages [Array<Message>] conversation messages
      # @return [String, nil] system message content
      def extract_system_message(messages)
        system_msg = messages.find { |m| m.role == Role::SYSTEM }
        system_msg&.content
      end

      # Format a single message for the Anthropic API
      # @param message [Message] conversation message with role, content, and optional tool data
      # @return [Hash] Anthropic-formatted message
      def format_message(message)
        case message.role
        when Role::USER
          { role: "user", content: format_user_content(message.content) }
        when Role::ASSISTANT
          { role: "assistant", content: format_assistant_content(message) }

        when Role::TOOL
          {
            role: "user",
            content: [{
              type: "tool_result",
              tool_use_id: message.tool_call_id,
              content: message.content.to_s
            }]
          }
        else
          raise ArgumentError, "Unknown role: #{message.role}"
        end
      end

      # Format user message content, handling text and media blocks
      # @param content [String, Array, Object] raw user content
      # @return [String, Array<Hash>] formatted content blocks
      def format_user_content(content)
        return content if content.is_a?(String)

        # Handle content blocks array (text + media)
        if content.is_a?(Array)
          content.map do |block|
            if block.is_a?(Hash) && block[:type] == "media"
              format_media_block(block[:media])
            elsif block.is_a?(Hash) && block[:type] == "text"
              { type: "text", text: block[:text] }
            elsif block.is_a?(String)
              { type: "text", text: block }
            else
              block
            end
          end
        else
          content.to_s
        end
      end

      # Format a media attachment as an Anthropic image source block
      # @param media [Media] attachment to convert to a base64 image source or text fallback
      # @return [Hash] Anthropic image or text fallback block
      def format_media_block(media)
        return { type: "text", text: "[unsupported media]" } unless media

        # Only images are supported for vision
        unless media.image? && Media::Processor::VISION_IMAGE_TYPES.include?(media.mime_type)
          return { type: "text", text: "[Attached: #{media.filename} (#{media.mime_type})]" }
        end

        # Get base64 data
        data = if media.data
                 media.data
               elsif media.path && File.exist?(media.path)
                 require "base64"
                 Base64.strict_encode64(File.binread(media.path))
               else
                 return { type: "text", text: "[Image not available]" }
               end

        {
          type: "image",
          source: {
            type: "base64",
            media_type: media.mime_type,
            data: data
          }
        }
      end

      # Normalize content to a string or array
      # @param content [String, Array, Object] raw message content to pass through or coerce to string
      # @return [String, Array] normalized content
      def format_content(content)
        return content if content.is_a?(String)
        return content if content.is_a?(Array)

        content.to_s
      end

      # Format assistant message content including tool use blocks
      # @param message [Message] assistant message with optional tool calls
      # @return [String, Array<Hash>] formatted content blocks
      def format_assistant_content(message)
        blocks = []

        blocks << { type: "text", text: message.content } if message.content && !message.content.empty?

        message.tool_calls&.each do |tc|
          blocks << {
            type: "tool_use",
            id: tc.id,
            name: tc.name,
            input: tc.arguments
          }
        end

        blocks.empty? ? "" : blocks
      end

      # Convert tool definitions to Anthropic format
      # @param tools [Array<Hash>, nil] tool definitions (OpenAI or Anthropic format)
      # @return [Array<Hash>, nil] Anthropic-formatted tool definitions
      def format_tools(tools)
        return nil if tools.nil? || tools.empty?

        tools.map do |tool|
          if tool[:function]
            # OpenAI-style format
            {
              name: tool[:function][:name],
              description: tool[:function][:description],
              input_schema: tool[:function][:parameters] || { type: "object", properties: {} }
            }
          else
            # Already in Anthropic format
            tool
          end
        end
      end

      # Handle HTTP response, raising on errors
      # @param response [Faraday::Response] HTTP response
      # @return [LLMResponse] parsed response
      # @raise [ProviderError] on non-success HTTP status
      def handle_response(response)
        unless response.success?
          error_body = begin
            JSON.parse(response.body)
          rescue StandardError
            { "error" => response.body }
          end
          raise ProviderError, "Anthropic API error: #{error_body["error"]}"
        end

        data = JSON.parse(response.body)
        parse_response(data)
      end

      # Parse Anthropic API response into an LLMResponse
      # @param data [Hash] parsed JSON response body
      # @return [LLMResponse] structured response with content, tool calls, and usage
      def parse_response(data)
        content = ""
        thinking = nil
        tool_calls = []

        data["content"]&.each do |block|
          case block["type"]
          when "text"
            content += block["text"]
          when "thinking"
            thinking = block["thinking"]
          when "tool_use"
            tool_calls << ToolCall.new(
              id: block["id"],
              name: block["name"],
              arguments: block["input"]
            )
          end
        end

        usage_data = data["usage"] || {}
        usage = Usage.new(
          input_tokens: usage_data["input_tokens"] || 0,
          output_tokens: usage_data["output_tokens"] || 0,
          cache_read: usage_data["cache_read_input_tokens"],
          cache_write: usage_data["cache_creation_input_tokens"]
        )

        stop_reason = case data["stop_reason"]
                      when "end_turn" then :end_turn
                      when "tool_use" then :tool_use
                      when "max_tokens" then :max_tokens
                      when "stop_sequence" then :stop_sequence
                      else :end_turn
                      end

        LLMResponse.new(
          content: content.empty? ? nil : content,
          tool_calls: tool_calls,
          usage: usage,
          stop_reason: stop_reason,
          model: data["model"],
          thinking: thinking
        )
      end

      # Process a single SSE chunk from the streaming response
      # @param chunk [String] raw SSE data chunk
      # @param accumulated_content [String] buffer for accumulated text content
      # @param _accumulated_tool_calls [Array<ToolCall>] buffer for tool calls (unused)
      # @param block [Proc] callback receiving each text delta
      # @return [void]
      def process_stream_chunk(chunk, accumulated_content, _accumulated_tool_calls, &block)
        chunk.split("\n").each do |line|
          next unless line.start_with?("data: ")

          data = begin
            JSON.parse(line[6..])
          rescue StandardError
            next
          end

          case data["type"]
          when "content_block_delta"
            if data.dig("delta", "type") == "text_delta"
              text = data.dig("delta", "text")
              accumulated_content << text if text
              block&.call(text)
            end
          when "content_block_start"
            if data.dig("content_block", "type") == "tool_use"
              # Tool use block starting
            end
          end
        end
      end
    end
  end
end
