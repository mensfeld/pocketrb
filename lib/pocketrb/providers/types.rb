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
      # Initialize LLM response
      # @param content [String, nil] Text content of the response
      # @param tool_calls [Array<ToolCall>] Tool calls requested by the model (defaults to empty)
      # @param usage [Usage, nil] Token usage statistics
      # @param stop_reason [Symbol] Reason for stopping (:end_turn, :tool_use, :max_tokens, :stop_sequence)
      # @param model [String, nil] Model that generated the response
      # @param thinking [String, nil] Extended thinking content (Claude)
      def initialize(content:, tool_calls: [], usage: nil, stop_reason: :end_turn, model: nil, thinking: nil)
        super
      end

      # Check if response has tool calls
      # @return [Boolean] True if tool calls are present
      def has_tool_calls?
        tool_calls && !tool_calls.empty?
      end

      # Check if response has text content
      # @return [Boolean] True if content is present
      def has_content?
        content && !content.empty?
      end

      # Check if response has thinking content
      # @return [Boolean] True if thinking is present
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
      # Initialize tool call
      # @param id [String] Unique identifier for this tool call
      # @param name [String] Name of the tool to execute
      # @param arguments [Hash, String] Arguments to pass to the tool (JSON string or hash)
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
      # Initialize token usage statistics
      # @param input_tokens [Integer] Tokens in the input (defaults to 0)
      # @param output_tokens [Integer] Tokens in the output (defaults to 0)
      # @param cache_read [Integer, nil] Tokens read from cache
      # @param cache_write [Integer, nil] Tokens written to cache
      def initialize(input_tokens: 0, output_tokens: 0, cache_read: nil, cache_write: nil)
        super
      end

      # Calculate total tokens used
      # @return [Integer] Sum of input and output tokens
      def total_tokens
        input_tokens + output_tokens
      end
    end

    # Message role for conversation history
    module Role
      # System message role
      SYSTEM = "system"
      # User message role
      USER = "user"
      # Assistant message role
      ASSISTANT = "assistant"
      # Tool result message role
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
      # Initialize message
      # @param role [String] Message role (system, user, assistant, or tool)
      # @param content [String, Array] Text content or content blocks
      # @param name [String, nil] For tool role, the tool name
      # @param tool_call_id [String, nil] For tool role, the tool call this responds to
      # @param tool_calls [Array<ToolCall>, nil] For assistant role, tool calls made
      def initialize(role:, content:, name: nil, tool_call_id: nil, tool_calls: nil)
        super
      end

      # Create a system message
      # @param content [String] System message content
      # @return [Message] New system message
      def self.system(content)
        new(role: Role::SYSTEM, content: content)
      end

      # Create a user message
      # @param content [String] User message content
      # @param media [Array<Media>, nil] Media attachments (images, files)
      # @return [Message] New user message
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

      # Create an assistant message
      # @param content [String] Assistant message content
      # @param tool_calls [Array<ToolCall>, nil] Tool calls made by the assistant
      # @return [Message] New assistant message
      def self.assistant(content, tool_calls: nil)
        new(role: Role::ASSISTANT, content: content, tool_calls: tool_calls)
      end

      # Create a tool result message
      # @param tool_call_id [String] Tool call identifier this result responds to
      # @param name [String] Name of the tool that was executed
      # @param content [String] Tool execution result content
      # @return [Message] New tool result message
      def self.tool_result(tool_call_id:, name:, content:)
        new(role: Role::TOOL, content: content, name: name, tool_call_id: tool_call_id)
      end
    end
  end
end
