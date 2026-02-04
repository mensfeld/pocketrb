# frozen_string_literal: true

module Pocketrb
  module Session
    # Represents a conversation session with history
    class Session
      attr_reader :key, :metadata, :created_at
      attr_accessor :messages

      def initialize(key:, messages: [], metadata: {})
        @key = key
        @messages = messages
        @metadata = metadata
        @created_at = Time.now
        @mutex = Mutex.new
      end

      # Add a message to the session
      # @param role [String] Message role
      # @param content [String] Message content
      # @param kwargs [Hash] Additional message attributes
      def add_message(role:, content:, **kwargs)
        @mutex.synchronize do
          message = Providers::Message.new(
            role: role,
            content: content,
            **kwargs
          )
          @messages << message
          save_to_log(message)
        end
      end

      # Add a user message (with optional media)
      # @param content [String] Text content
      # @param media [Array<Bus::Media>] Media attachments
      def add_user_message(content, media: nil)
        if media && !media.empty?
          # Build content blocks with text and media references
          # Note: We store media metadata, not the actual data
          blocks = []
          blocks << { type: "text", text: content } if content && !content.empty?

          media.each do |m|
            blocks << {
              type: "media",
              media: {
                type: m.type,
                path: m.path.to_s,
                mime_type: m.mime_type,
                filename: m.filename
                # Don't store base64 data in session - too large
              }
            }
          end

          add_message(role: Providers::Role::USER, content: blocks)
        else
          add_message(role: Providers::Role::USER, content: content)
        end
      end

      # Add an assistant message
      def add_assistant_message(content, tool_calls: nil)
        # Truncate large tool call arguments to prevent context bloat
        sanitized_calls = sanitize_tool_calls(tool_calls) if tool_calls
        add_message(role: Providers::Role::ASSISTANT, content: content, tool_calls: sanitized_calls)
      end

      # Add a tool result message
      MAX_TOOL_RESULT_LENGTH = 2000

      def add_tool_result(tool_call_id:, name:, content:)
        # Truncate large tool results to prevent context bloat
        truncated_content = if content.is_a?(String) && content.length > MAX_TOOL_RESULT_LENGTH
                              "#{content[0...MAX_TOOL_RESULT_LENGTH]}... [truncated #{content.length - MAX_TOOL_RESULT_LENGTH} chars]"
                            else
                              content
                            end

        add_message(
          role: Providers::Role::TOOL,
          content: truncated_content,
          name: name,
          tool_call_id: tool_call_id
        )
      end

      # Get message history (optionally limited)
      # @param max_messages [Integer|nil] Maximum messages to return
      # @return [Array<Message>]
      def get_history(max_messages: nil)
        @mutex.synchronize do
          return @messages.dup if max_messages.nil?

          @messages.last(max_messages)
        end
      end

      # Clear all messages
      def clear
        @mutex.synchronize do
          @messages.clear
        end
      end

      # Get the last message
      def last_message
        @mutex.synchronize { @messages.last }
      end

      # Number of messages
      def message_count
        @mutex.synchronize { @messages.size }
      end

      # Check if session is empty
      def empty?
        @mutex.synchronize { @messages.empty? }
      end

      # Set metadata value
      def set_meta(key, value)
        @mutex.synchronize { @metadata[key] = value }
      end

      # Get metadata value
      def get_meta(key)
        @mutex.synchronize { @metadata[key] }
      end

      # Convert to hash for serialization
      def to_h
        @mutex.synchronize do
          {
            key: @key,
            messages: @messages.map(&:to_h),
            metadata: @metadata,
            created_at: @created_at.iso8601
          }
        end
      end

      # Create from hash
      def self.from_h(hash)
        messages = (hash[:messages] || hash["messages"] || []).map do |m|
          Providers::Message.new(
            role: m[:role] || m["role"],
            content: m[:content] || m["content"],
            name: m[:name] || m["name"],
            tool_call_id: m[:tool_call_id] || m["tool_call_id"],
            tool_calls: m[:tool_calls] || m["tool_calls"]
          )
        end

        session = new(
          key: hash[:key] || hash["key"],
          messages: messages,
          metadata: hash[:metadata] || hash["metadata"] || {}
        )
        session.instance_variable_set(
          :@created_at,
          Time.parse(hash[:created_at] || hash["created_at"])
        )
        session
      rescue StandardError => e
        Pocketrb.logger.error("Failed to load session: #{e.message}")
        new(key: hash[:key] || hash["key"])
      end

      private

      # Truncate large arguments in tool calls to prevent context bloat
      # Large content (scripts, files) shouldn't be stored in session history
      MAX_ARG_LENGTH = 500

      def sanitize_tool_calls(tool_calls)
        return nil if tool_calls.nil?

        tool_calls.map do |tc|
          sanitized_args = tc.arguments.transform_values do |v|
            if v.is_a?(String) && v.length > MAX_ARG_LENGTH
              "#{v[0...MAX_ARG_LENGTH]}... [truncated #{v.length - MAX_ARG_LENGTH} chars]"
            else
              v
            end
          end

          # Create new tool call with sanitized arguments
          Providers::ToolCall.new(
            id: tc.id,
            name: tc.name,
            arguments: sanitized_args
          )
        end
      end

      def save_to_log(message)
        # Session manager handles persistence via JSONL
        # This is a hook for real-time logging if needed
      end
    end
  end
end
