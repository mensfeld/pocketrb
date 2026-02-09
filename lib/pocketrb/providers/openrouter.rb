# frozen_string_literal: true

require "faraday"
require "json"

# Pocketrb: Ruby AI agent with multi-LLM support and advanced planning capabilities
module Pocketrb
  # LLM provider implementations
  module Providers
    # OpenRouter API provider for multi-model access
    # Supports Claude, GPT-4, Llama, and many other models
    class OpenRouter < Base
      # OpenRouter API base URL
      API_URL = "https://openrouter.ai/api/v1"

      # Popular models available through OpenRouter
      POPULAR_MODELS = %w[
        anthropic/claude-sonnet-4
        anthropic/claude-3.5-haiku
        openai/gpt-4o
        openai/gpt-4o-mini
        google/gemini-pro-1.5
        meta-llama/llama-3.1-70b-instruct
        mistralai/mistral-large
      ].freeze

      # Provider name
      # @return [Symbol]
      def name
        :openrouter
      end

      # Default model
      # @return [String]
      def default_model
        "anthropic/claude-sonnet-4"
      end

      # Available models
      # @return [Array<String>]
      def available_models
        # Could fetch from API, but use popular models for now
        POPULAR_MODELS
      end

      # Send chat completion request
      # @param messages [Array<Message>] Conversation messages
      # @param tools [Array<Hash>, nil] Tool definitions
      # @param model [String, nil] Model name (e.g., "anthropic/claude-sonnet-4")
      # @param temperature [Float] Sampling temperature
      # @param max_tokens [Integer] Maximum tokens to generate
      # @param thinking [Boolean] Enable extended thinking (model-dependent)
      # @return [LLMResponse] Parsed response
      def chat(messages:, tools: nil, model: nil, temperature: 0.7, max_tokens: 4096, thinking: false)
        model ||= default_model
        body = build_request_body(messages, tools, model, temperature, max_tokens)

        response = client.post("/api/v1/chat/completions") do |req|
          req.body = body.to_json
        end

        handle_response(response)
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
        body = build_request_body(messages, tools, model, temperature, max_tokens)
        body[:stream] = true

        accumulated_content = ""
        accumulated_tool_calls = []

        client.post("/api/v1/chat/completions") do |req|
          req.body = body.to_json
          req.options.on_data = proc do |chunk, _|
            process_stream_chunk(chunk, accumulated_content, accumulated_tool_calls, &block)
          end
        end

        LLMResponse.new(
          content: accumulated_content,
          tool_calls: accumulated_tool_calls,
          model: model
        )
      end

      protected

      def supported_features
        %i[tools streaming]
      end

      def validate_config!
        require_api_key!(:openrouter_api_key)
      end

      private

      def client
        @client ||= Faraday.new(url: API_URL) do |f|
          f.headers["Content-Type"] = "application/json"
          f.headers["Authorization"] = "Bearer #{api_key(:openrouter_api_key)}"
          f.headers["HTTP-Referer"] = @config[:site_url] || "https://github.com/mensfeld/pocketrb"
          f.headers["X-Title"] = @config[:app_name] || "Pocketrb"
          f.adapter Faraday.default_adapter
        end
      end

      def build_request_body(messages, tools, model, temperature, max_tokens)
        body = {
          model: model,
          messages: format_messages(messages),
          temperature: temperature,
          max_tokens: max_tokens
        }

        body[:tools] = tools if tools&.any?

        body
      end

      def format_message(message)
        case message.role
        when Role::SYSTEM
          { role: "system", content: message.content }
        when Role::USER
          { role: "user", content: message.content }
        when Role::ASSISTANT
          msg = { role: "assistant", content: message.content }
          if message.tool_calls&.any?
            msg[:tool_calls] = message.tool_calls.map do |tc|
              {
                id: tc.id,
                type: "function",
                function: { name: tc.name, arguments: tc.arguments.to_json }
              }
            end
          end
          msg
        when Role::TOOL
          {
            role: "tool",
            tool_call_id: message.tool_call_id,
            content: message.content.to_s
          }
        else
          raise ArgumentError, "Unknown role: #{message.role}"
        end
      end

      def handle_response(response)
        unless response.success?
          error_body = begin
            JSON.parse(response.body)
          rescue StandardError
            { "error" => response.body }
          end
          raise ProviderError, "OpenRouter API error: #{error_body["error"]}"
        end

        data = JSON.parse(response.body)
        parse_response(data)
      end

      def parse_response(data)
        choice = data.dig("choices", 0)
        return LLMResponse.new(content: nil) unless choice

        message = choice["message"]
        content = message["content"]

        tool_calls = (message["tool_calls"] || []).map do |tc|
          ToolCall.new(
            id: tc["id"],
            name: tc.dig("function", "name"),
            arguments: tc.dig("function", "arguments")
          )
        end

        usage_data = data["usage"] || {}
        usage = Usage.new(
          input_tokens: usage_data["prompt_tokens"] || 0,
          output_tokens: usage_data["completion_tokens"] || 0
        )

        stop_reason = case choice["finish_reason"]
                      when "stop" then :end_turn
                      when "tool_calls" then :tool_use
                      when "length" then :max_tokens
                      else :end_turn
                      end

        LLMResponse.new(
          content: content,
          tool_calls: tool_calls,
          usage: usage,
          stop_reason: stop_reason,
          model: data["model"]
        )
      end

      def process_stream_chunk(chunk, accumulated_content, _accumulated_tool_calls, &block)
        chunk.split("\n").each do |line|
          next unless line.start_with?("data: ")
          next if line == "data: [DONE]"

          data = begin
            JSON.parse(line[6..])
          rescue StandardError
            next
          end
          delta = data.dig("choices", 0, "delta")
          next unless delta

          if delta["content"]
            accumulated_content << delta["content"]
            block&.call(delta["content"])
          end
        end
      end
    end
  end
end
