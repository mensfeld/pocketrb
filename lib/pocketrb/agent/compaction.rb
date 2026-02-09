# frozen_string_literal: true

module Pocketrb
  module Agent
    # Context compaction to summarize long conversations and save tokens
    class Compaction
      # Default thresholds (balanced for context retention)
      DEFAULT_MESSAGE_THRESHOLD = 40      # Compact when exceeding this many messages
      DEFAULT_TOKEN_THRESHOLD = 50_000    # Compact when exceeding this many estimated tokens
      DEFAULT_KEEP_RECENT = 15            # Keep this many recent messages uncompacted
      CHARS_PER_TOKEN = 4                 # Rough estimate for token counting

      COMPACTION_PROMPT = <<~PROMPT
        Summarize this conversation history concisely. Include:
        - Key decisions made
        - Important information learned
        - Current task/goal if any
        - Any pending items or context needed for continuation

        Keep the summary under 500 words. Focus on information the assistant needs to continue effectively.
      PROMPT

      attr_reader :provider, :model
      attr_accessor :message_threshold, :token_threshold, :keep_recent

      # Initialize a new compaction instance
      # @param provider [Object] LLM provider instance for generating summaries
      # @param model [String, nil] Model name to use for summarization (defaults to provider default)
      # @param message_threshold [Integer, nil] Maximum messages before compaction (defaults to DEFAULT_MESSAGE_THRESHOLD)
      # @param token_threshold [Integer, nil] Maximum estimated tokens before compaction (defaults to DEFAULT_TOKEN_THRESHOLD)
      # @param keep_recent [Integer, nil] Number of recent messages to keep uncompacted (defaults to DEFAULT_KEEP_RECENT)
      def initialize(provider:, model: nil, message_threshold: nil, token_threshold: nil, keep_recent: nil)
        @provider = provider
        @model = model || provider.default_model
        @message_threshold = message_threshold || DEFAULT_MESSAGE_THRESHOLD
        @token_threshold = token_threshold || DEFAULT_TOKEN_THRESHOLD
        @keep_recent = keep_recent || DEFAULT_KEEP_RECENT
      end

      # Check if compaction is needed for messages
      # @param messages [Array<Message>] Conversation messages
      # @return [Boolean]
      def needs_compaction?(messages)
        return false if messages.size <= @keep_recent

        messages.size > @message_threshold || estimate_tokens(messages) > @token_threshold
      end

      # Compact messages by summarizing older ones
      # @param messages [Array<Message>] Conversation messages (excluding system)
      # @return [Array<Message>] Compacted messages
      def compact(messages)
        return messages unless needs_compaction?(messages)

        # Split messages: older ones to summarize, recent ones to keep
        split_point = [messages.size - @keep_recent, 0].max
        to_summarize = messages[0...split_point]

        return messages if to_summarize.empty?

        # Adjust split point to keep tool_use/tool_result pairs together
        split_point = adjust_split_for_tool_pairs(messages, split_point)
        to_summarize = messages[0...split_point]
        to_keep = messages[split_point..]

        Pocketrb.logger.info("Compacting #{to_summarize.size} messages into summary")

        # Generate summary
        summary = generate_summary(to_summarize)

        # Build compacted message list
        compacted = []
        compacted << build_summary_message(summary)
        compacted.concat(to_keep)

        compacted
      end

      # Compact a session's messages in place
      # @param session [Session::Session] Session object containing messages to be compacted
      # @return [Boolean] Whether compaction occurred
      def compact_session!(session)
        messages = session.messages.dup
        return false unless needs_compaction?(messages)

        # Filter out system messages for compaction
        user_assistant_messages = messages.reject { |m| m.role == Providers::Role::SYSTEM }
        return false if user_assistant_messages.size <= @keep_recent

        compacted = compact(user_assistant_messages)

        # Update session
        session.messages.clear
        compacted.each { |m| session.messages << m }

        Pocketrb.logger.info("Session compacted: #{messages.size} -> #{compacted.size} messages")
        true
      end

      # Estimate token count for messages
      # @param messages [Array<Message>] Array of messages to analyze for token count estimation
      # @return [Integer] Estimated tokens
      def estimate_tokens(messages)
        total_chars = messages.sum do |msg|
          content = msg.content
          if content.is_a?(Array)
            # Content blocks (text + media references)
            content.sum do |block|
              if block.is_a?(Hash) && block[:type] == "text"
                block[:text].to_s.length
              elsif block.is_a?(String)
                block.length
              else
                50 # Estimate for non-text blocks
              end
            end
          else
            content.to_s.length
          end
        end

        (total_chars / CHARS_PER_TOKEN).to_i
      end

      private

      # Adjust split point to keep tool_use/tool_result pairs together
      # If a tool_result is in the kept messages, ensure its corresponding
      # assistant message with tool_calls is also kept
      # @param messages [Array<Message>] All messages
      # @param split_point [Integer] Initial split point
      # @return [Integer] Adjusted split point
      def adjust_split_for_tool_pairs(messages, split_point)
        return split_point if split_point.zero?

        to_keep = messages[split_point..]

        # Find all tool results in the kept messages
        tool_call_ids = to_keep
                        .select { |m| m.role == Providers::Role::TOOL }
                        .filter_map(&:tool_call_id)
                        .compact

        return split_point if tool_call_ids.empty?

        # Find the earliest assistant message with matching tool_calls that needs to be kept
        earliest_tool_use_index = nil

        messages[0...split_point].each_with_index do |msg, idx|
          next unless msg.role == Providers::Role::ASSISTANT && msg.tool_calls

          # Check if any tool_calls match the tool_results we're keeping
          matching_tools = msg.tool_calls.select { |tc| tool_call_ids.include?(tc.id) }
          if matching_tools.any?
            earliest_tool_use_index = idx
            break
          end
        end

        # Adjust split point to include the assistant message with tool_calls
        if earliest_tool_use_index
          Pocketrb.logger.debug(
            "Adjusted split point from #{split_point} to #{earliest_tool_use_index} " \
            "to keep tool_use/tool_result pairs together"
          )
          earliest_tool_use_index
        else
          split_point
        end
      end

      def generate_summary(messages)
        # Format messages for summarization
        formatted = format_for_summary(messages)

        summary_request = [
          Providers::Message.system(COMPACTION_PROMPT),
          Providers::Message.user("Conversation history to summarize:\n\n#{formatted}")
        ]

        response = @provider.chat(
          messages: summary_request,
          model: @model,
          max_tokens: 1000
        )

        response.content || "Previous conversation summary unavailable."
      rescue StandardError => e
        Pocketrb.logger.error("Compaction summary failed: #{e.message}")
        # Fallback: create basic summary
        basic_summary(messages)
      end

      def format_for_summary(messages)
        messages.map do |msg|
          role = msg.role.capitalize
          content = extract_text_content(msg.content)
          "#{role}: #{content[0..500]}#{"..." if content.length > 500}"
        end.join("\n\n")
      end

      def extract_text_content(content)
        if content.is_a?(Array)
          content.filter_map do |block|
            if block.is_a?(Hash) && block[:type] == "text"
              block[:text]
            elsif block.is_a?(String)
              block
            end
          end.join("\n")
        else
          content.to_s
        end
      end

      def build_summary_message(summary)
        Providers::Message.user(
          "[Previous conversation summary]\n#{summary}\n[End of summary - continuing conversation]"
        )
      end

      def basic_summary(messages)
        # Create a very basic summary without LLM
        user_count = messages.count { |m| m.role == Providers::Role::USER }
        assistant_count = messages.count { |m| m.role == Providers::Role::ASSISTANT }
        tool_count = messages.count { |m| m.role == Providers::Role::TOOL }

        parts = ["Previous conversation: #{user_count} user messages, #{assistant_count} assistant responses"]
        parts << "#{tool_count} tool calls" if tool_count.positive?

        # Extract last few user queries for context
        recent_queries = messages.select { |m| m.role == Providers::Role::USER }
                                 .last(3)
                                 .map { |m| "- #{extract_text_content(m.content)[0..100]}" }

        parts << "Recent topics:\n#{recent_queries.join("\n")}" unless recent_queries.empty?

        parts.join("\n\n")
      end
    end
  end
end
