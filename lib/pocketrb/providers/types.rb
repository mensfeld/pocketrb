# frozen_string_literal: true

module Pocketrb
  module Providers
    # Response from an LLM provider
    LLMResponse = Data.define(
      :content,      # String|nil - text content of the response
      :tool_calls,   # Array<ToolCall> - tool calls requested by the model
      :usage,        # Usage - token usage statistics
      :stop_reason,  # Symbol - :end_turn, :tool_use, :max_tokens, :stop_sequence
      :model,        # String - model that generated the response
      :thinking      # String|nil - extended thinking content (Claude)
    ) do
      def initialize(content:, tool_calls: [], usage: nil, stop_reason: :end_turn, model: nil, thinking: nil)
        super
      end

      def has_tool_calls?
        tool_calls && !tool_calls.empty?
      end

      def has_content?
        content && !content.empty?
      end

      def has_thinking?
        thinking && !thinking.empty?
      end
    end

    # Tool call from the model
    ToolCall = Data.define(
      :id,           # String - unique identifier for this tool call
      :name,         # String - name of the tool to execute
      :arguments     # Hash - arguments to pass to the tool
    ) do
      def initialize(id:, name:, arguments:)
        args = arguments.is_a?(String) ? JSON.parse(arguments) : arguments
        super(id: id, name: name, arguments: args)
      rescue JSON::ParserError
        super(id: id, name: name, arguments: {})
      end
    end

    # Token usage statistics
    Usage = Data.define(
      :input_tokens,   # Integer - tokens in the input
      :output_tokens,  # Integer - tokens in the output
      :cache_read,     # Integer|nil - tokens read from cache
      :cache_write     # Integer|nil - tokens written to cache
    ) do
      def initialize(input_tokens: 0, output_tokens: 0, cache_read: nil, cache_write: nil)
        super
      end

      def total_tokens
        input_tokens + output_tokens
      end
    end

    # Message role for conversation history
    module Role
      SYSTEM = "system"
      USER = "user"
      ASSISTANT = "assistant"
      TOOL = "tool"
    end

    # Message in conversation history
    Message = Data.define(
      :role,         # String - Role::SYSTEM, USER, ASSISTANT, or TOOL
      :content,      # String|Array - text content or content blocks
      :name,         # String|nil - for tool role, the tool name
      :tool_call_id, # String|nil - for tool role, the tool call this responds to
      :tool_calls    # Array<ToolCall>|nil - for assistant role, tool calls made
    ) do
      def initialize(role:, content:, name: nil, tool_call_id: nil, tool_calls: nil)
        super
      end

      def self.system(content)
        new(role: Role::SYSTEM, content: content)
      end

      def self.user(content, media: nil)
        if media && !media.empty?
          # Build content blocks array with text and images
          blocks = []
          blocks << { type: "text", text: content } if content && !content.empty?

          media.each do |m|
            # Media will be formatted by the provider
            blocks << { type: "media", media: m }
          end

          new(role: Role::USER, content: blocks)
        else
          new(role: Role::USER, content: content)
        end
      end

      def self.assistant(content, tool_calls: nil)
        new(role: Role::ASSISTANT, content: content, tool_calls: tool_calls)
      end

      def self.tool_result(tool_call_id:, name:, content:)
        new(role: Role::TOOL, content: content, name: name, tool_call_id: tool_call_id)
      end
    end
  end
end
