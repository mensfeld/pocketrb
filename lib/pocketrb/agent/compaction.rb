# frozen_string_literal: true

module Pocketrb
  module Agent
    # Context compaction to summarize long conversations and save tokens
    class Compaction
      # Default thresholds (balanced for context retention)
      DEFAULT_MESSAGE_THRESHOLD = 40      # Compact when exceeding this many messages
      DEFAULT_TOKEN_THRESHOLD = 50_000    # Compact when exceeding this many estimated tokens
      DEFAULT_KEEP_RECENT = 15            # Keep this many recent messages uncompacted
      DEFAULT_CONTEXT_PRESSURE = 0.7      # Compact when estimated tokens exceed this fraction of context window
      CHARS_PER_TOKEN = 4                 # Rough estimate for token counting

      COMPACTION_PROMPT = <<~PROMPT
        Summarize this conversation history concisely. Include:
        - Key decisions made
        - Important information learned
        - Current task/goal if any
        - Any pending items or context needed for continuation

        If a prior conversation summary is provided, incorporate its key points into your new summary
        so that important context is preserved across compaction cycles.

        Keep the summary under 500 words. Focus on information the assistant needs to continue effectively.
      PROMPT

      attr_reader :provider, :model, :context_window, :context_pressure, :on_compact
      attr_accessor :message_threshold, :token_threshold, :keep_recent

      # Initialize a new compaction instance
      # @param provider [Object] LLM provider instance for generating summaries
      # @param model [String, nil] Model name to use for summarization (defaults to provider default)
      # @param message_threshold [Integer, nil] Maximum messages before compaction (defaults to DEFAULT_MESSAGE_THRESHOLD)
      # @param token_threshold [Integer, nil] Maximum estimated tokens before compaction (defaults to DEFAULT_TOKEN_THRESHOLD)
      # @param keep_recent [Integer, nil] Number of recent messages to keep uncompacted (defaults to DEFAULT_KEEP_RECENT)
      # @param context_window [Integer, nil] Model context window size in tokens (defaults to provider value)
      # @param context_pressure [Float, nil] Fraction of context window that triggers compaction (defaults to DEFAULT_CONTEXT_PRESSURE)
      # @param on_compact [Proc, nil] Callback called after compaction with (summary, compacted_count)
      def initialize(
        provider:,
        model: nil,
        message_threshold: nil,
        token_threshold: nil,
        keep_recent: nil,
        context_window: nil,
        context_pressure: nil,
        on_compact: nil
      )
        @provider = provider
        @model = model || provider.default_model
        @message_threshold = message_threshold || DEFAULT_MESSAGE_THRESHOLD
        @token_threshold = token_threshold || DEFAULT_TOKEN_THRESHOLD
        @keep_recent = keep_recent || DEFAULT_KEEP_RECENT
        @context_window = context_window || provider.context_window(model: @model)
        validate_context_window!(@context_window)
        @context_pressure = context_pressure || DEFAULT_CONTEXT_PRESSURE
        validate_context_pressure!(@context_pressure)
        @on_compact = on_compact
        @compact_mutex = Mutex.new
        @compacting = false
      end

      # Check if compaction is needed for messages
      # @param messages [Array<Message>] Conversation messages
      # @return [Boolean]
      def needs_compaction?(messages)
        return false if messages.size <= @keep_recent
        return true if messages.size > @message_threshold

        estimated = estimate_tokens(messages)
        return true if estimated > @token_threshold

        # Pressure-based: trigger when estimated tokens exceed configured fraction of context window
        estimated > @context_window * @context_pressure
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

        # Extract prior summary for rolling context preservation
        prior_summary = extract_prior_summary(to_summarize)

        # Exclude the prior summary message from to_summarize to avoid duplication
        to_summarize = to_summarize[1..] if prior_summary && !to_summarize.empty?

        Pocketrb.logger.info("Compacting #{to_summarize.size} messages into summary")

        # Generate summary (incorporating prior summary if present)
        summary = generate_summary(to_summarize, prior_summary: prior_summary)
        compacted_count = to_summarize.size

        # Build compacted message list
        compacted = []
        compacted << build_summary_message(summary)
        compacted.concat(to_keep)

        @on_compact&.call(summary, compacted_count)

        compacted
      end

      # Compact a session's messages in place (synchronous)
      # @param session [Session::Session] Session object containing messages to be compacted
      # @return [Boolean] Whether compaction occurred
      def compact_session!(session)
        @compact_mutex.synchronize do
          perform_session_compaction(session)
        end
      end

      # Schedule asynchronous compaction in a background thread
      # @param session [Session::Session] Session object containing messages to be compacted
      # @return [Thread, nil] Background thread or nil if compaction not needed or already running
      def schedule_compaction(session)
        # Guard check-and-set under mutex to prevent concurrent scheduling
        thread = @compact_mutex.synchronize do
          return nil if @compacting

          messages = session.messages.dup
          return nil unless needs_compaction?(messages)

          @compacting = true

          Thread.new do
            @compact_mutex.synchronize do
              perform_session_compaction(session)
            ensure
              @compacting = false
            end
          end
        end

        @compact_thread = thread
      end

      # Whether background compaction is currently running
      # @return [Boolean]
      def compacting?
        @compacting
      end

      # Wait for any in-progress background compaction to finish
      # @param timeout [Integer, nil] Maximum seconds to wait (nil = wait forever)
      # @return [Boolean] true if compaction finished, false if timed out
      def wait_for_compaction(timeout: nil)
        return true unless @compact_thread&.alive?

        if timeout
          @compact_thread.join(timeout) ? true : false
        else
          @compact_thread.join
          true
        end
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

      def validate_context_window!(value)
        return if value.is_a?(Numeric) && value.positive?

        raise ArgumentError, "context_window must be a positive number (got #{value.inspect})"
      end

      def validate_context_pressure!(value)
        return if value.is_a?(Numeric) && value >= 0.0 && value <= 1.0

        raise ArgumentError, "context_pressure must be between 0.0 and 1.0 (got #{value.inspect})"
      end

      # Perform the actual session compaction (must be called under compaction mutex)
      # @param session [Session::Session] Session to compact
      # @return [Boolean] Whether compaction occurred
      def perform_session_compaction(session)
        # Snapshot messages under session lock to avoid races with add_message
        messages, user_assistant_messages = session.with_lock do
          msgs = session.messages.dup
          ua = msgs.reject { |m| m.role == Providers::Role::SYSTEM }
          [msgs, ua]
        end

        return false unless needs_compaction?(messages)
        return false if user_assistant_messages.size <= @keep_recent

        compacted = compact(user_assistant_messages)

        # Replace session messages under session lock
        session.with_lock do
          session.messages.clear
          compacted.each { |m| session.messages << m }
        end

        Pocketrb.logger.info("Session compacted: #{messages.size} -> #{compacted.size} messages")
        true
      end

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

      # Extract prior summary text from messages if the first message is a summary
      # @param messages [Array<Message>] Messages to check
      # @return [String, nil] Prior summary text or nil
      def extract_prior_summary(messages)
        return nil if messages.empty?

        first = messages[0]
        content = first.content.to_s

        # Strict detection: must start with the marker and contain the end marker
        start_marker = "[Previous conversation summary]"
        end_marker = "[End of summary"
        return nil unless content.start_with?(start_marker) && content.include?(end_marker)

        # Extract the summary text between markers
        match = content.match(/\[Previous conversation summary\]\n(.*?)\n\[End of summary/m)
        match ? match[1] : nil
      end

      def generate_summary(messages, prior_summary: nil)
        # Format messages for summarization
        formatted = format_for_summary(messages)

        user_content = "Conversation history to summarize:\n\n#{formatted}"

        if prior_summary
          user_content = "Prior summary from earlier conversation:\n#{prior_summary}\n\n#{user_content}"
        end

        summary_request = [
          Providers::Message.system(COMPACTION_PROMPT),
          Providers::Message.user(user_content)
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
