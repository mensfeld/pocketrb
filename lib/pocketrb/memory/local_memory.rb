# frozen_string_literal: true

require "json"

module Pocketrb
  module Memory
    # Local structured memory for facts and recent events
    # Complements MCP/QMD vector memory with structured recall
    class LocalMemory
      MAX_RECENT_EVENTS = 50

      attr_reader :workspace

      def initialize(workspace:)
        @workspace = Pathname.new(workspace)
        @memory_dir = @workspace.join(".pocketrb", "memory")
        @facts_file = @memory_dir.join("facts.json")
        @recent_file = @memory_dir.join("recent.json")
        @identity_dir = @memory_dir.join("identity")

        ensure_dirs!
        load_data!
      end

      # === Long-term Facts ===

      # Remember something is installed
      def remember_installed(name, details = nil)
        @facts["installed"][name] = {
          "installed_at" => Time.now.utc.iso8601,
          "details" => details
        }
        save_facts!
        "Remembered: #{name} is installed"
      end

      # Remember something learned about a topic
      def remember_learned(topic, info)
        @facts["learned"][topic] ||= []
        @facts["learned"][topic] << {
          "info" => info,
          "learned_at" => Time.now.utc.iso8601
        }
        save_facts!
        "Remembered: learned about #{topic}"
      end

      # Remember something about the user
      def remember_user(key, value)
        @facts["user"][key] = {
          "value" => value,
          "updated_at" => Time.now.utc.iso8601
        }
        save_facts!
        "Remembered: user's #{key} is #{value}"
      end

      # Remember something about self
      def remember_self(key, value)
        @facts["self"][key] = {
          "value" => value,
          "updated_at" => Time.now.utc.iso8601
        }
        save_facts!
        "Remembered: my #{key} is #{value}"
      end

      # Check if something is installed
      def installed?(name)
        @facts["installed"].key?(name)
      end

      # List installed items
      def list_installed
        @facts["installed"].keys
      end

      # Recall learned info about a topic
      def recall_learned(topic)
        @facts["learned"][topic]
      end

      # Recall user info
      def recall_user(key = nil)
        key ? @facts["user"][key] : @facts["user"]
      end

      # Recall self info
      def recall_self(key = nil)
        key ? @facts["self"][key] : @facts["self"]
      end

      # === Short-term Memory (Recent Events) ===

      def add_event(event_type, description)
        @recent.unshift({
                          "type" => event_type,
                          "description" => description,
                          "timestamp" => Time.now.utc.iso8601
                        })
        @recent = @recent.first(MAX_RECENT_EVENTS)
        save_recent!
      end

      def recent_events(count = 10)
        @recent.first(count)
      end

      # === Context for LLM ===

      # Get relevant context based on message content
      def relevant_context(message)
        message_lower = message.downcase
        summary = []

        # Always include identity
        identity = load_identity
        summary << "MY IDENTITY: #{identity}" if identity && !identity.empty?

        # Always include self info
        if @facts["self"].any?
          self_info = @facts["self"].map { |k, v| "#{k}: #{v["value"]}" }.join(", ")
          summary << "ABOUT ME: #{self_info}"
        end

        # Include user info
        if @facts["user"].any?
          user_info = @facts["user"].map { |k, v| "#{k}: #{v["value"]}" }.join(", ")
          summary << "USER: #{user_info}"
        end

        # Include installed software only if message mentions related keywords
        install_keywords = %w[install package pip npm gem bundle apt brew]
        if @facts["installed"].any? && install_keywords.any? { |kw| message_lower.include?(kw) }
          summary << "ALREADY INSTALLED: #{@facts["installed"].keys.join(", ")}"
        end

        # Include learned facts that match keywords in the message
        @facts["learned"].each do |topic, entries|
          next unless message_lower.include?(topic.downcase)

          info = begin
            entries.last["info"]
          rescue StandardError
            entries.to_s
          end
          summary << "KNOWN ABOUT #{topic}: #{info}"
        end

        # Recent events (last 3 only)
        if @recent.any?
          recent = @recent.first(3).map { |e| "- #{e["description"]}" }.join("\n")
          summary << "RECENT:\n#{recent}"
        end

        summary.join("\n\n")
      end

      # Full context summary
      def context_summary
        summary = []

        summary << "INSTALLED: #{@facts["installed"].keys.join(", ")}" if @facts["installed"].any?

        if @facts["user"].any?
          user_info = @facts["user"].map { |k, v| "#{k}: #{v["value"]}" }.join(", ")
          summary << "USER: #{user_info}"
        end

        if @facts["self"].any?
          self_info = @facts["self"].map { |k, v| "#{k}: #{v["value"]}" }.join(", ")
          summary << "ABOUT ME: #{self_info}"
        end

        if @recent.any?
          recent = @recent.first(5).map { |e| "- #{e["description"]}" }.join("\n")
          summary << "RECENT:\n#{recent}"
        end

        summary.join("\n\n")
      end

      # Dump all data
      def to_h
        {
          "facts" => @facts,
          "recent" => @recent
        }
      end

      private

      def ensure_dirs!
        FileUtils.mkdir_p(@memory_dir)
        FileUtils.mkdir_p(@identity_dir)
      end

      def load_data!
        @facts = load_json(@facts_file) || {
          "installed" => {},
          "learned" => {},
          "user" => {},
          "self" => {}
        }
        @recent = load_json(@recent_file) || []
      end

      def load_json(path)
        return nil unless path.exist?

        JSON.parse(File.read(path))
      rescue JSON::ParserError
        nil
      end

      def save_facts!
        File.write(@facts_file, JSON.pretty_generate(@facts))
      end

      def save_recent!
        File.write(@recent_file, JSON.pretty_generate(@recent))
      end

      def load_identity
        return nil unless @identity_dir.exist?

        identity = []
        Dir.glob(@identity_dir.join("*")).each do |file|
          next if File.directory?(file)

          key = File.basename(file, ".*").tr("_", " ")
          value = begin
            File.read(file).strip
          rescue StandardError
            next
          end
          identity << "#{key}: #{value}" unless value.empty?
        end
        identity.join(", ")
      end
    end
  end
end
