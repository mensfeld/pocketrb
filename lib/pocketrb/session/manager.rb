# frozen_string_literal: true

require "json"

module Pocketrb
  module Session
    # Manages session persistence using JSONL files
    class Manager
      attr_reader :storage_dir

      def initialize(storage_dir:)
        @storage_dir = Pathname.new(storage_dir)
        @sessions = {}
        @mutex = Mutex.new

        ensure_storage_dir!
      end

      # Get or create a session
      # @param key [String] Session key
      # @return [Session]
      def get_or_create(key)
        @mutex.synchronize do
          @sessions[key] ||= load_or_create(key)
        end
      end

      # Get an existing session
      # @param key [String] Session key
      # @return [Session|nil]
      def get(key)
        @mutex.synchronize do
          @sessions[key] || load_session(key)
        end
      end

      # Save a session
      # @param session [Session]
      def save(session)
        @mutex.synchronize do
          @sessions[session.key] = session
          persist_session(session)
        end
      end

      # Delete a session
      # @param key [String] Session key
      def delete(key)
        @mutex.synchronize do
          @sessions.delete(key)
          delete_session_file(key)
        end
      end

      # List all session keys
      # @return [Array<String>]
      def list_keys
        @mutex.synchronize do
          loaded = @sessions.keys
          persisted = Dir.glob(@storage_dir.join("*.jsonl")).map do |f|
            File.basename(f, ".jsonl")
          end
          (loaded + persisted).uniq
        end
      end

      # Append a message to a session's JSONL file (real-time logging)
      # @param key [String] Session key
      # @param message [Message]
      def append_message(key, message)
        @mutex.synchronize do
          file = session_file(key)
          File.open(file, "a") do |f|
            f.puts(message.to_h.to_json)
          end
        end
      end

      # Clear all sessions
      def clear_all!
        @mutex.synchronize do
          @sessions.clear
          Dir.glob(@storage_dir.join("*.jsonl")).each { |f| File.delete(f) }
        end
      end

      private

      def ensure_storage_dir!
        FileUtils.mkdir_p(@storage_dir) unless @storage_dir.exist?
      end

      def session_file(key)
        # Sanitize key for filename
        safe_key = key.gsub(/[^a-zA-Z0-9_-]/, "_")
        @storage_dir.join("#{safe_key}.jsonl")
      end

      def load_or_create(key)
        load_session(key) || Session.new(key: key)
      end

      def load_session(key)
        file = session_file(key)
        return nil unless file.exist?

        messages = []
        File.foreach(file) do |line|
          next if line.strip.empty?

          data = JSON.parse(line.strip)
          messages << Providers::Message.new(
            role: data["role"],
            content: data["content"],
            name: data["name"],
            tool_call_id: data["tool_call_id"],
            tool_calls: parse_tool_calls(data["tool_calls"])
          )
        end

        Session.new(key: key, messages: messages)
      rescue JSON::ParserError => e
        Pocketrb.logger.error("Failed to parse session #{key}: #{e.message}")
        Session.new(key: key)
      end

      def parse_tool_calls(tool_calls)
        return nil unless tool_calls

        tool_calls.map do |tc|
          Providers::ToolCall.new(
            id: tc["id"],
            name: tc["name"],
            arguments: tc["arguments"]
          )
        end
      end

      def persist_session(session)
        file = session_file(session.key)
        File.open(file, "w") do |f|
          session.messages.each do |msg|
            f.puts(message_to_json(msg))
          end
        end
      end

      def message_to_json(message)
        {
          role: message.role,
          content: message.content,
          name: message.name,
          tool_call_id: message.tool_call_id,
          tool_calls: message.tool_calls&.map do |tc|
            { id: tc.id, name: tc.name, arguments: tc.arguments }
          end
        }.compact.to_json
      end

      def delete_session_file(key)
        file = session_file(key)
        File.delete(file) if file.exist?
      end
    end
  end
end
