# frozen_string_literal: true

module Pocketrb
  module Memory
    # QMD (Query Memory Database) integration for vector-based semantic memory
    # Combines local memory with QMD for hybrid memory system
    class QMD
      attr_reader :client, :local_memory, :daily_notes

      def initialize(workspace:, endpoint: nil)
        @workspace = Pathname.new(workspace)
        @endpoint = endpoint || ENV["MCP_ENDPOINT"] || "http://localhost:7878"
        @client = MCP::Client.new(endpoint: @endpoint)
        @local_memory = LocalMemory.new(workspace: workspace)
        @daily_notes = DailyNotes.new(workspace: workspace)
        @connected = false
      end

      # Connect to QMD server
      # @return [Boolean] Whether connection succeeded
      def connect
        @connected = @client.connect
        Pocketrb.logger.info("QMD connected: #{@connected}")
        @connected
      rescue StandardError => e
        Pocketrb.logger.warn("QMD connection failed: #{e.message}")
        @connected = false
      end

      # Check if connected to QMD
      def connected?
        @connected && @client.connected?
      end

      # Search memory (QMD + local)
      # @param query [String] Search query
      # @param limit [Integer] Max results
      # @return [Hash] Combined results from QMD and local memory
      def search(query, limit: 10)
        results = {
          qmd: [],
          local: nil,
          daily: nil
        }

        # Search QMD if connected
        if connected?
          begin
            qmd_results = @client.search(query: query, limit: limit)
            results[:qmd] = parse_qmd_results(qmd_results)
          rescue StandardError => e
            Pocketrb.logger.warn("QMD search failed: #{e.message}")
          end
        end

        # Search local memory
        results[:local] = @local_memory.relevant_context(query)

        # Search daily notes
        daily_matches = @daily_notes.search(query, days: 14)
        results[:daily] = format_daily_matches(daily_matches) if daily_matches.any?

        results
      end

      # Store to memory (QMD + local)
      # @param content [String] Content to store
      # @param metadata [Hash] Additional metadata
      # @param category [Symbol] Category for local memory (:learned, :user, :self)
      # @return [Boolean] Whether store succeeded
      def store(content, metadata: {}, category: :learned)
        success = true

        # Store to QMD if connected
        if connected?
          begin
            qmd_metadata = metadata.merge(
              timestamp: Time.now.iso8601,
              source: "pocketrb",
              workspace: @workspace.basename.to_s
            )
            @client.store(content: content, metadata: qmd_metadata)
          rescue StandardError => e
            Pocketrb.logger.warn("QMD store failed: #{e.message}")
            success = false
          end
        end

        # Also store locally based on category
        case category
        when :learned
          topic = metadata[:topic] || "general"
          @local_memory.remember_learned(topic, content)
        when :user
          key = metadata[:key] || "info"
          @local_memory.remember_user(key, content)
        when :self
          key = metadata[:key] || "info"
          @local_memory.remember_self(key, content)
        end

        # Add to daily notes
        @daily_notes.write_note(content[0..200], category: category.to_s)

        success
      end

      # Get relevant context for a message (for LLM system prompt)
      # @param message [String] The user message
      # @return [String] Context string for system prompt
      def relevant_context(message)
        parts = []

        # Get local memory context (identity, user info, etc.)
        local_ctx = @local_memory.relevant_context(message)
        parts << local_ctx unless local_ctx.empty?

        # Get recent daily notes
        daily_ctx = @daily_notes.context_summary(days: 3)
        parts << "RECENT NOTES:\n#{daily_ctx}" unless daily_ctx.empty?

        # Get QMD semantic search results
        if connected?
          begin
            qmd_results = @client.search(query: message, limit: 5)
            qmd_ctx = format_qmd_context(qmd_results)
            parts << "RELEVANT MEMORIES:\n#{qmd_ctx}" unless qmd_ctx.empty?
          rescue StandardError => e
            Pocketrb.logger.debug("QMD context search failed: #{e.message}")
          end
        end

        parts.join("\n\n")
      end

      # Remember something (convenience method)
      # @param content [String] What to remember
      # @param type [Symbol] Type of memory (:fact, :event, :preference)
      # @param metadata [Hash] Additional metadata
      def remember(content, type: :fact, metadata: {})
        case type
        when :fact, :learned
          store(content, metadata: metadata, category: :learned)
        when :event
          @local_memory.add_event(metadata[:event_type] || "general", content)
          @daily_notes.write_note(content, category: "event")
        when :preference, :user
          store(content, metadata: metadata, category: :user)
        when :self
          store(content, metadata: metadata, category: :self)
        else
          store(content, metadata: metadata.merge(type: type), category: :learned)
        end
      end

      # Recall from memory
      # @param query [String] What to recall
      # @return [String] Recalled information
      def recall(query)
        results = search(query, limit: 5)
        format_recall_results(results)
      end

      # Get full memory summary
      # @return [String] Summary of all memory sources
      def summary
        parts = []

        parts << "LOCAL MEMORY:\n#{@local_memory.context_summary}"

        daily = @daily_notes.context_summary(days: 7)
        parts << "DAILY NOTES (7 days):\n#{daily}" unless daily.empty?

        if connected?
          parts << "QMD: Connected to #{@endpoint}"
        else
          parts << "QMD: Not connected"
        end

        parts.join("\n\n")
      end

      # Sync local memory to QMD
      # @return [Integer] Number of items synced
      def sync_to_qmd
        return 0 unless connected?

        count = 0

        # Sync learned facts
        @local_memory.to_h.dig("facts", "learned")&.each do |topic, entries|
          entries.each do |entry|
            begin
              @client.store(
                content: entry["info"],
                metadata: {
                  topic: topic,
                  learned_at: entry["learned_at"],
                  source: "local_memory_sync"
                }
              )
              count += 1
            rescue StandardError
              # Skip failed entries
            end
          end
        end

        Pocketrb.logger.info("Synced #{count} items to QMD")
        count
      end

      private

      def parse_qmd_results(results)
        return [] if results.nil?

        if results.is_a?(String)
          # Parse text response
          [{ content: results, score: 1.0 }]
        elsif results.is_a?(Array)
          results.map do |r|
            {
              content: r["content"] || r["text"] || r.to_s,
              score: r["score"],
              metadata: r["metadata"]
            }
          end
        elsif results.is_a?(Hash) && results["results"]
          parse_qmd_results(results["results"])
        else
          []
        end
      end

      def format_qmd_context(results)
        parsed = parse_qmd_results(results)
        return "" if parsed.empty?

        parsed.map { |r| "- #{r[:content][0..300]}" }.join("\n")
      end

      def format_daily_matches(matches)
        matches.map do |m|
          "#{m[:date]}: #{m[:matches].join('; ')}"
        end.join("\n")
      end

      def format_recall_results(results)
        parts = []

        if results[:qmd].any?
          parts << "From long-term memory:"
          results[:qmd].each_with_index do |r, i|
            parts << "  #{i + 1}. #{r[:content][0..200]}"
          end
        end

        parts << results[:local] if results[:local] && !results[:local].empty?
        parts << "From daily notes:\n#{results[:daily]}" if results[:daily]

        parts.empty? ? "No relevant memories found." : parts.join("\n\n")
      end
    end
  end
end
