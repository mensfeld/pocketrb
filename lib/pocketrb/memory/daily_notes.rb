# frozen_string_literal: true

require "date"
require "fileutils"

module Pocketrb
  module Memory
    # Date-based memory files for daily notes and learnings
    class DailyNotes
      attr_reader :workspace

      def initialize(workspace:)
        @workspace = Pathname.new(workspace)
        @memory_dir = @workspace.join("memory")
      end

      # Read today's notes
      # @return [String, nil] Today's notes content or nil if none
      def read_today
        return nil unless today_file.exist?

        today_file.read
      end

      # Append content to today's notes
      # @param content [String] Content to append
      # @return [String] Confirmation message
      def append_today(content)
        ensure_dir!
        File.open(today_file, "a") do |f|
          f.puts(content)
          f.puts # Add blank line for separation
        end
        "Added to #{Date.today} notes"
      end

      # Write structured note entry with timestamp
      # @param content [String] Note content
      # @param category [String, nil] Optional category (e.g., "learned", "todo", "idea")
      # @return [String] Confirmation message
      def write_note(content, category: nil)
        ensure_dir!
        timestamp = Time.now.strftime("%H:%M")
        entry = if category
                  "- [#{timestamp}] **#{category}**: #{content}"
                else
                  "- [#{timestamp}] #{content}"
                end
        append_today(entry)
      end

      # Get recent daily notes
      # @param days [Integer] Number of days to look back
      # @return [Array<Hash>] Array of { date:, content: } hashes
      def get_recent(days: 7)
        (0...days).filter_map do |offset|
          date = Date.today - offset
          file = file_for_date(date)
          next unless file.exist?

          { date: date, content: file.read }
        end
      end

      # Read notes for a specific date
      # @param date [Date, String] The date to read
      # @return [String, nil] Notes content or nil
      def read_date(date)
        date = Date.parse(date.to_s) unless date.is_a?(Date)
        file = file_for_date(date)
        return nil unless file.exist?

        file.read
      end

      # Search notes for a keyword
      # @param query [String] Search query
      # @param days [Integer] Days to search back
      # @return [Array<Hash>] Matching entries with date and lines
      def search(query, days: 30)
        results = []
        query_lower = query.downcase

        (0...days).each do |offset|
          date = Date.today - offset
          file = file_for_date(date)
          next unless file.exist?

          matching_lines = file.readlines.select { |line| line.downcase.include?(query_lower) }
          next if matching_lines.empty?

          results << { date: date, matches: matching_lines.map(&:strip) }
        end

        results
      end

      # List all daily note files
      # @return [Array<Date>] Dates with notes
      def list_dates
        return [] unless @memory_dir.exist?

        Dir.glob(@memory_dir.join("*.md")).filter_map do |file|
          basename = File.basename(file, ".md")
          Date.parse(basename)
        rescue Date::Error
          nil
        end.sort.reverse
      end

      # Get summary for context (last N days)
      # @param days [Integer] Days to summarize
      # @return [String] Summary for LLM context
      def context_summary(days: 3)
        notes = get_recent(days: days)
        return "" if notes.empty?

        notes.map do |entry|
          "## #{entry[:date]}\n#{entry[:content]}"
        end.join("\n\n")
      end

      private

      def ensure_dir!
        FileUtils.mkdir_p(@memory_dir)
      end

      def today_file
        file_for_date(Date.today)
      end

      def file_for_date(date)
        @memory_dir.join("#{date}.md")
      end
    end
  end
end
