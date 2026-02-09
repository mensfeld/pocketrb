# frozen_string_literal: true

# Pocketrb: Ruby AI agent with multi-LLM support and advanced planning capabilities
module Pocketrb
  # Tool implementations for agent capabilities
  module Tools
    # Simple memory tool - store and recall facts
    class Memory < Base
      # Available memory actions
      ACTIONS = %w[store recall search recent stats].freeze
      # Memory categories for organization
      CATEGORIES = %w[learned user preference context].freeze

      # Tool name
      # @return [String]
      def name
        "memory"
      end

      # Tool description
      # @return [String]
      def description
        <<~DESC.strip
          Store and recall memories. Use this to remember important facts, preferences, and learnings.

          Actions:
          - store: Save a fact (categories: learned, user, preference, context)
          - recall: Search for memories matching a query
          - search: Deep search across all memory categories
          - recent: Show recent events
          - stats: Memory statistics
        DESC
      end

      # Parameter schema
      # @return [Hash]
      def parameters
        {
          type: "object",
          properties: {
            action: {
              type: "string",
              enum: ACTIONS,
              description: "Memory action to perform"
            },
            category: {
              type: "string",
              enum: CATEGORIES,
              description: "Category for storing (learned, user, preference, context)"
            },
            key: {
              type: "string",
              description: "Key/topic for the memory"
            },
            value: {
              type: "string",
              description: "Value/content to store"
            },
            query: {
              type: "string",
              description: "Search query for recall/search actions"
            }
          },
          required: ["action"]
        }
      end

      # Check if tool is available
      # @return [Boolean] true if memory system is initialized
      def available?
        !memory_instance.nil?
      end

      # Execute memory action
      # @param action [String] Action to perform (store, recall, search, recent, stats)
      # @param category [String, nil] Category for storing memories
      # @param key [String, nil] Memory key or topic
      # @param value [String, nil] Memory content to store
      # @param query [String, nil] Search query for recall/search
      # @return [String] Action result or error message
      def execute(action:, category: nil, key: nil, value: nil, query: nil, **)
        return error("Memory not initialized") unless memory_instance

        case action
        when "store"
          store_memory(category, key, value)
        when "recall"
          recall_memory(query)
        when "search"
          search_memory(query)
        when "recent"
          show_recent
        when "stats"
          show_stats
        else
          error("Unknown action: #{action}")
        end
      rescue StandardError => e
        error("Memory error: #{e.message}")
      end

      private

      def memory_instance
        @context[:memory]
      end

      def store_memory(category, key, value)
        return error("Category, key, and value required") unless category && key && value

        result = case category
                 when "learned"
                   memory_instance.remember_learned(key, value)
                 when "user"
                   memory_instance.remember_user(key, value)
                 when "preference"
                   memory_instance.remember_preference(key, value)
                 when "context"
                   memory_instance.remember_context(key, value)
                 else
                   return error("Invalid category. Use: learned, user, preference, or context")
                 end

        success(result)
      end

      def recall_memory(query)
        return error("Query required") unless query

        context = memory_instance.relevant_context(query, max_facts: 10)

        if context.empty?
          "No relevant memories found for: #{query}"
        else
          "Relevant memories:\n\n#{context}"
        end
      end

      def search_memory(query)
        return error("Query required") unless query

        results = memory_instance.search(query)

        return "No memories found matching: #{query}" if results.empty?

        lines = ["Found #{results.size} memories:"]
        results.each_with_index do |result, i|
          lines << "\n#{i + 1}. [#{result[:type]}] #{result[:topic] || result[:key]}"
          lines << "   #{result[:content] || result[:value]}"
          lines << "   (#{result[:date]})" if result[:date]
        end

        lines.join("\n")
      end

      def show_recent
        events = memory_instance.recent_events(10)

        return "No recent events recorded." if events.empty?

        lines = ["Recent events (#{events.size}):"]
        events.each do |event|
          timestamp = Time.parse(event["timestamp"]).strftime("%Y-%m-%d %H:%M")
          lines << "- [#{timestamp}] #{event["description"]}"
        end

        lines.join("\n")
      end

      def show_stats
        stats = memory_instance.stats

        lines = [
          "Memory Statistics:",
          "- Learned topics: #{stats[:learned_topics]} (#{stats[:total_learned]} total facts)",
          "- User facts: #{stats[:user_facts]}",
          "- Preferences: #{stats[:preferences]}",
          "- Context items: #{stats[:context_items]}",
          "- Recent events: #{stats[:recent_events]}"
        ]

        lines.join("\n")
      end
    end
  end
end
