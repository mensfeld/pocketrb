# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Pocketrb
  module Providers
    # Claude Max API Proxy provider
    # Uses the claude-max-api-proxy which provides OpenAI-compatible API
    # Install: npm install -g claude-max-api-proxy
    # Start: claude-max-api (runs on localhost:3456)
    class ClaudeMaxProxy < Base
      # Available model aliases mapped to full model names
      MODELS = {
        "opus" => "claude-opus-4",
        "sonnet" => "claude-sonnet-4",
        "haiku" => "claude-haiku-4"
      }.freeze

      # Default model alias
      DEFAULT_MODEL = "sonnet"
      # Default base URL for claude-max-api proxy
      DEFAULT_BASE_URL = "http://localhost:3456/v1"

      # Initialize Claude Max Proxy provider
      # @param config [Hash] Configuration options (base_url, etc.)
      def initialize(config = {})
        @config = config
        @base_url = config[:base_url] || ENV["CLAUDE_MAX_PROXY_URL"] || DEFAULT_BASE_URL
        validate_config!
      end

      # Provider name
      # @return [Symbol] Provider identifier
      def name
        :claude_max_proxy
      end

      # Default model for this provider
      # @return [String] Default model alias
      def default_model
        DEFAULT_MODEL
      end

      # List of available model aliases
      # @return [Array<String>] Model alias names
      def available_models
        MODELS.keys
      end

      # Send a chat request
      # @param messages [Array<Message>] Conversation history
      # @param tools [Array<Hash>, nil] Available tools for the model to use
      # @param model [String, nil] Model name (defaults to DEFAULT_MODEL)
      # @param temperature [Float] Temperature for response randomness (0.0-1.0)
      # @param max_tokens [Integer] Maximum tokens in response
      # @param thinking [Boolean] Enable extended thinking mode (not used for this provider)
      # @return [LLMResponse] Model response
      def chat(messages:, tools: nil, model: nil, temperature: 0.7, max_tokens: 4096, thinking: false)
        model ||= default_model
        model_id = MODELS[model] || model

        body = build_request_body(
          messages: messages,
          model: model_id,
          tools: tools,
          temperature: temperature,
          max_tokens: max_tokens,
          stream: false
        )

        response = make_request("/chat/completions", body)
        parse_response(response, model_id)
      end

      # Send a streaming chat request
      # @param messages [Array<Message>] Conversation history
      # @param tools [Array<Hash>, nil] Available tools for the model to use
      # @param model [String, nil] Model name (defaults to DEFAULT_MODEL)
      # @param temperature [Float] Temperature for response randomness (0.0-1.0)
      # @param max_tokens [Integer] Maximum tokens in response
      # @yieldparam chunk [String] Text chunk from streaming response
      # @return [LLMResponse] Final complete response
      def chat_stream(messages:, tools: nil, model: nil, temperature: 0.7, max_tokens: 4096, &)
        model ||= default_model
        model_id = MODELS[model] || model

        body = build_request_body(
          messages: messages,
          model: model_id,
          tools: tools,
          temperature: temperature,
          max_tokens: max_tokens,
          stream: true
        )

        stream_request("/chat/completions", body, &)
      end

      # Check if proxy is running
      def available?
        uri = URI.parse("#{@base_url.sub("/v1", "")}/health")
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 2
        http.read_timeout = 2
        response = http.get(uri.path)
        response.code == "200"
      rescue StandardError
        false
      end

      protected

      def supported_features
        %i[tools streaming]
      end

      def validate_config!
        # No API key needed - proxy uses CLI auth
        Pocketrb.logger.debug("Claude Max Proxy: #{@base_url}")
      end

      private

      def build_request_body(messages:, model:, tools:, temperature:, max_tokens:, stream:)
        body = {
          model: model,
          messages: format_messages(messages),
          temperature: temperature,
          max_tokens: max_tokens,
          stream: stream
        }

        if tools && !tools.empty?
          body[:tools] = format_tools(tools)
          body[:tool_choice] = "auto"
        end

        body
      end

      def format_messages(messages)
        messages.map do |msg|
          formatted = { role: msg.role.to_s }

          formatted[:content] = if msg.content.is_a?(Array)
                                  # Handle multi-part content (text + images)
                                  msg.content.map do |part|
                                    if part[:type] == "media" && part[:media]&.image?
                                      format_image_content(part[:media])
                                    elsif part[:type] == "text"
                                      { type: "text", text: part[:text] }
                                    else
                                      { type: "text", text: part.to_s }
                                    end
                                  end
                                else
                                  msg.content
                                end

          # Handle tool calls
          if msg.tool_calls && !msg.tool_calls.empty?
            formatted[:tool_calls] = msg.tool_calls.map do |tc|
              {
                id: tc.id,
                type: "function",
                function: {
                  name: tc.name,
                  arguments: tc.arguments.is_a?(String) ? tc.arguments : tc.arguments.to_json
                }
              }
            end
          end

          # Handle tool results
          if msg.tool_call_id
            formatted[:tool_call_id] = msg.tool_call_id
            formatted[:name] = msg.name if msg.name
          end

          formatted
        end
      end

      def format_image_content(media)
        if media.data
          {
            type: "image_url",
            image_url: {
              url: "data:#{media.mime_type};base64,#{media.data}"
            }
          }
        elsif media.path && File.exist?(media.path)
          require "base64"
          data = Base64.strict_encode64(File.binread(media.path))
          {
            type: "image_url",
            image_url: {
              url: "data:#{media.mime_type};base64,#{data}"
            }
          }
        else
          { type: "text", text: "[Image: #{media.filename}]" }
        end
      end

      def format_tools(tools)
        tools.map do |tool|
          func = tool[:function] || tool
          {
            type: "function",
            function: {
              name: func[:name],
              description: func[:description],
              parameters: func[:parameters] || func[:input_schema] || {}
            }
          }
        end
      end

      def make_request(endpoint, body)
        uri = URI.parse("#{@base_url}#{endpoint}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 30
        http.read_timeout = 300

        request = Net::HTTP::Post.new(uri.path)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer not-needed" # Proxy doesn't need auth
        request.body = body.to_json

        response = http.request(request)

        unless response.code.to_i == 200
          error_body = begin
            JSON.parse(response.body)
          rescue StandardError
            { "error" => response.body }
          end
          raise ProviderError, "Claude Max Proxy error (#{response.code}): #{error_body["error"] || error_body}"
        end

        JSON.parse(response.body)
      end

      def stream_request(endpoint, body, &block)
        uri = URI.parse("#{@base_url}#{endpoint}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 30
        http.read_timeout = 300

        request = Net::HTTP::Post.new(uri.path)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer not-needed"
        request["Accept"] = "text/event-stream"
        request.body = body.to_json

        full_content = ""
        tool_calls = []
        model_used = body[:model]

        http.request(request) do |response|
          unless response.code.to_i == 200
            error_body = response.read_body
            raise ProviderError, "Claude Max Proxy stream error (#{response.code}): #{error_body}"
          end

          buffer = ""
          response.read_body do |chunk|
            buffer += chunk
            while (line_end = buffer.index("\n"))
              line = buffer.slice!(0..line_end).strip
              next if line.empty? || line == "data: [DONE]"
              next unless line.start_with?("data: ")

              begin
                data = JSON.parse(line[6..])
                delta = data.dig("choices", 0, "delta")
                next unless delta

                if delta["content"]
                  full_content += delta["content"]
                  block&.call(delta["content"])
                end

                # Handle streaming tool calls
                delta["tool_calls"]&.each do |tc|
                  idx = tc["index"]
                  tool_calls[idx] ||= { id: "", name: "", arguments: "" }
                  tool_calls[idx][:id] = tc["id"] if tc["id"]
                  tool_calls[idx][:name] = tc.dig("function", "name") if tc.dig("function", "name")
                  tool_calls[idx][:arguments] += tc.dig("function", "arguments") || ""
                end
              rescue JSON::ParserError
                # Skip malformed JSON
              end
            end
          end
        end

        # Build final response
        parsed_tool_calls = tool_calls.compact.map do |tc|
          args = begin
            JSON.parse(tc[:arguments])
          rescue JSON::ParserError
            {}
          end
          ToolCall.new(
            id: tc[:id],
            name: tc[:name],
            arguments: args
          )
        end

        LLMResponse.new(
          content: full_content.empty? ? nil : full_content,
          tool_calls: parsed_tool_calls,
          usage: Usage.new(input_tokens: 0, output_tokens: 0),
          stop_reason: parsed_tool_calls.any? ? :tool_use : :end_turn,
          model: model_used
        )
      end

      def parse_response(response, model)
        choice = response.dig("choices", 0)
        message = choice&.dig("message") || {}

        content = message["content"]
        tool_calls = parse_tool_calls(message["tool_calls"])

        usage_data = response["usage"] || {}
        usage = Usage.new(
          input_tokens: usage_data["prompt_tokens"] || 0,
          output_tokens: usage_data["completion_tokens"] || 0
        )

        stop_reason = case choice&.dig("finish_reason")
                      when "tool_calls" then :tool_use
                      when "stop" then :end_turn
                      when "length" then :max_tokens
                      else :end_turn
                      end

        LLMResponse.new(
          content: content,
          tool_calls: tool_calls,
          usage: usage,
          stop_reason: stop_reason,
          model: model
        )
      end

      def parse_tool_calls(tool_calls)
        return [] unless tool_calls

        tool_calls.map do |tc|
          args = begin
            JSON.parse(tc.dig("function", "arguments") || "{}")
          rescue JSON::ParserError
            {}
          end
          ToolCall.new(
            id: tc["id"],
            name: tc.dig("function", "name"),
            arguments: args
          )
        end
      end
    end
  end
end
