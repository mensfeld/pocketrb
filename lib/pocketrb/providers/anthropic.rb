# frozen_string_literal: true

require "faraday"
require "json"

module Pocketrb
  module Providers
    # Direct Anthropic Claude API provider
    # Supports extended thinking and all Claude-specific features
    class Anthropic < Base
      API_URL = "https://api.anthropic.com/v1"
      API_VERSION = "2023-06-01"

      MODELS = {
        "claude-opus-4-20250514" => { context: 200_000, output: 32_000 },
        "claude-sonnet-4-20250514" => { context: 200_000, output: 64_000 },
        "claude-3-5-haiku-20241022" => { context: 200_000, output: 8192 }
      }.freeze

      def name
        :anthropic
      end

      def default_model
        "claude-sonnet-4-20250514"
      end

      def available_models
        MODELS.keys
      end

      def chat(messages:, tools: nil, model: nil, temperature: 0.7, max_tokens: 4096, thinking: false)
        model ||= default_model
        body = build_request_body(messages, tools, model, temperature, max_tokens, thinking)

        response = client.post("/v1/messages") do |req|
          req.body = body.to_json
        end

        handle_response(response)
      end

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

      def supported_features
        %i[tools streaming thinking vision]
      end

      def validate_config!
        return if oauth_token
        return if api_key(:anthropic_api_key)

        raise ConfigurationError,
              "Either ANTHROPIC_OAUTH_TOKEN or ANTHROPIC_API_KEY is required for #{self.class.name}"
      end

      private

      # Check for OAuth token (Max subscription via `claude setup-token`)
      def oauth_token
        @config[:anthropic_oauth_token] || ENV["ANTHROPIC_OAUTH_TOKEN"]
      end

      def using_oauth?
        !oauth_token.nil?
      end

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

        if thinking
          body[:thinking] = { type: "enabled", budget_tokens: [max_tokens / 2, 10_000].min }
        end

        body
      end

      def extract_system_message(messages)
        system_msg = messages.find { |m| m.role == Role::SYSTEM }
        system_msg&.content
      end

      def format_message(message)
        case message.role
        when Role::USER
          { role: "user", content: format_user_content(message.content) }
        when Role::ASSISTANT
          msg = { role: "assistant", content: format_assistant_content(message) }
          msg
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

      def format_content(content)
        return content if content.is_a?(String)
        return content if content.is_a?(Array)

        content.to_s
      end

      def format_assistant_content(message)
        blocks = []

        if message.content && !message.content.empty?
          blocks << { type: "text", text: message.content }
        end

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

      def handle_response(response)
        unless response.success?
          error_body = JSON.parse(response.body) rescue { "error" => response.body }
          raise ProviderError, "Anthropic API error: #{error_body["error"]}"
        end

        data = JSON.parse(response.body)
        parse_response(data)
      end

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

      def process_stream_chunk(chunk, accumulated_content, accumulated_tool_calls, &block)
        chunk.split("\n").each do |line|
          next unless line.start_with?("data: ")

          data = JSON.parse(line[6..]) rescue next

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
