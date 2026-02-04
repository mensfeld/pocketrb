# frozen_string_literal: true

require "json"
require "fileutils"

module Pocketrb
  # Simple memory system for facts and recent events
  # Inspired by nanobot - no vector DB, just JSON + keyword matching
  class Memory
    # Maximum number of recent events to keep
    MAX_RECENT = 50

    # Initialize memory system
    # @param workspace [String, Pathname] workspace directory
    def initialize(workspace:)
      @workspace = Pathname.new(workspace)
      @memory_dir = @workspace.join("memory")
      @memory_dir.mkpath

      @facts_file = @memory_dir.join("facts.json")
      @recent_file = @memory_dir.join("recent.json")

      @facts = load_json(@facts_file) || { "learned" => {}, "user" => {}, "preferences" => {}, "context" => {} }
      @recent = load_json(@recent_file) || []
    end

    # === Long-term facts ===

    # Remember something learned
    # @param topic [String] topic name
    # @param info [String] information about the topic
    # @return [String] confirmation message
    def remember_learned(topic, info)
      @facts["learned"][topic] ||= []
      @facts["learned"][topic] << {
        "info" => info,
        "learned_at" => Time.now.utc.iso8601
      }
      save_facts
      "Remembered: learned about #{topic}"
    end

    # Remember user preference/info
    # @param key [String] user attribute key
    # @param value [String] user attribute value
    # @return [String] confirmation message
    def remember_user(key, value)
      @facts["user"][key] = {
        "value" => value,
        "updated_at" => Time.now.utc.iso8601
      }
      save_facts
      "Remembered: user's #{key} is #{value}"
    end

    # Remember preference
    # @param key [String] preference key
    # @param value [String] preference value
    # @return [String] confirmation message
    def remember_preference(key, value)
      @facts["preferences"][key] = {
        "value" => value,
        "updated_at" => Time.now.utc.iso8601
      }
      save_facts
      "Remembered preference: #{key} = #{value}"
    end

    # Remember general context
    # @param key [String] context key
    # @param value [String] context value
    # @return [String] confirmation message
    def remember_context(key, value)
      @facts["context"][key] = {
        "value" => value,
        "updated_at" => Time.now.utc.iso8601
      }
      save_facts
      "Remembered: #{key}"
    end

    # Recall learned facts about a topic
    # @param topic [String] topic name
    # @return [Array, nil] learned facts or nil
    def recall_learned(topic)
      @facts["learned"][topic]
    end

    # Recall user info
    # @param key [String, nil] specific key to recall, or nil for all
    # @return [Hash, String, nil] user info
    def recall_user(key = nil)
      key ? @facts["user"][key] : @facts["user"]
    end

    # Recall preferences
    # @param key [String, nil] specific key to recall, or nil for all
    # @return [Hash, String, nil] preferences
    def recall_preferences(key = nil)
      key ? @facts["preferences"][key] : @facts["preferences"]
    end

    # === Recent events ===

    # Add a recent event
    # @param description [String] event description
    # @param category [String] event category (default: "general")
    # @return [void]
    def add_event(description, category: "general")
      @recent.unshift({
                        "category" => category,
                        "description" => description,
                        "timestamp" => Time.now.utc.iso8601
                      })
      @recent = @recent.first(MAX_RECENT)
      save_recent
    end

    # Get recent events
    # @param count [Integer] number of events to return (default: 10)
    # @return [Array<Hash>] recent events
    def recent_events(count = 10)
      @recent.first(count)
    end

    # === Context building for LLM ===

    # Get relevant memories for a message
    # @param message [String] message to find relevant context for
    # @param max_facts [Integer] maximum number of facts to include (default: 10)
    # @return [String] formatted context string
    def relevant_context(message, max_facts: 10)
      message_lower = message.downcase
      parts = []

      # User info
      if @facts["user"].any?
        user_info = @facts["user"].map { |k, v| "#{k}: #{v["value"]}" }.join(", ")
        parts << "USER: #{user_info}"
      end

      # Preferences
      if @facts["preferences"].any?
        prefs = @facts["preferences"].map { |k, v| "#{k}: #{v["value"]}" }.join(", ")
        parts << "PREFERENCES: #{prefs}"
      end

      # Learned facts matching keywords
      matched_facts = 0
      @facts["learned"].each do |topic, entries|
        break if matched_facts >= max_facts

        next unless message_lower.include?(topic.downcase)

        info = begin
          entries.last["info"]
        rescue StandardError
          entries.to_s
        end
        parts << "KNOWN ABOUT #{topic}: #{info}"
        matched_facts += 1
      end

      # Context items matching keywords
      @facts["context"].each do |key, data|
        break if matched_facts >= max_facts

        if message_lower.include?(key.downcase)
          parts << "#{key.upcase}: #{data["value"]}"
          matched_facts += 1
        end
      end

      # Recent events (last 5)
      if @recent.any?
        recent = @recent.first(5).map { |e| "- #{e["description"]}" }.join("\n")
        parts << "RECENT:\n#{recent}"
      end

      parts.join("\n\n")
    end

    # Search across all memories
    # @param query [String] search query
    # @return [Array<Hash>] search results
    def search(query)
      results = []
      query_lower = query.downcase

      # Search learned facts
      @facts["learned"].each do |topic, entries|
        next unless topic.downcase.include?(query_lower)

        entries.each do |entry|
          results << {
            type: "learned",
            topic: topic,
            content: entry["info"],
            date: entry["learned_at"]
          }
        end
      end

      # Search user info
      @facts["user"].each do |key, data|
        next unless key.downcase.include?(query_lower) || data["value"].to_s.downcase.include?(query_lower)

        results << {
          type: "user",
          key: key,
          value: data["value"],
          date: data["updated_at"]
        }
      end

      # Search preferences
      @facts["preferences"].each do |key, data|
        next unless key.downcase.include?(query_lower) || data["value"].to_s.downcase.include?(query_lower)

        results << {
          type: "preference",
          key: key,
          value: data["value"],
          date: data["updated_at"]
        }
      end

      # Search context
      @facts["context"].each do |key, data|
        next unless key.downcase.include?(query_lower) || data["value"].to_s.downcase.include?(query_lower)

        results << {
          type: "context",
          key: key,
          value: data["value"],
          date: data["updated_at"]
        }
      end

      results
    end

    # Get memory statistics
    def stats
      {
        learned_topics: @facts["learned"].keys.size,
        total_learned: @facts["learned"].values.sum(&:size),
        user_facts: @facts["user"].size,
        preferences: @facts["preferences"].size,
        context_items: @facts["context"].size,
        recent_events: @recent.size
      }
    end

    # Dump all memories (for debugging)
    def dump_all
      {
        "facts" => @facts,
        "recent" => @recent
      }
    end

    private

    def load_json(path)
      return nil unless path.exist?

      JSON.parse(path.read)
    rescue JSON::ParserError
      nil
    end

    def save_facts
      @facts_file.write(JSON.pretty_generate(@facts))
    end

    def save_recent
      @recent_file.write(JSON.pretty_generate(@recent))
    end
  end
end
