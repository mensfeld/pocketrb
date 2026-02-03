# frozen_string_literal: true

module Pocketrb
  module Heartbeat
    # Periodic wake-up service that checks HEARTBEAT.md for pending tasks
    class Service
      DEFAULT_INTERVAL = 30 * 60 # 30 minutes
      HEARTBEAT_FILE = "HEARTBEAT.md"

      HEARTBEAT_PROMPT = <<~PROMPT.freeze
        Read HEARTBEAT.md in your workspace. Follow any instructions or tasks listed there.
        If nothing needs attention, reply with: HEARTBEAT_OK

        Guidelines:
        - Complete any tasks listed in HEARTBEAT.md
        - Mark completed tasks as done (check the checkbox)
        - If a task cannot be completed, explain why
        - Only reply HEARTBEAT_OK if the file is empty or contains no actionable items
      PROMPT

      attr_reader :interval, :enabled, :last_run_at

      def initialize(workspace:, on_heartbeat:, interval: DEFAULT_INTERVAL, enabled: true)
        @workspace = Pathname.new(workspace)
        @on_heartbeat = on_heartbeat
        @interval = interval
        @enabled = enabled
        @running = false
        @timer_thread = nil
        @last_run_at = nil
        @mutex = Mutex.new
      end

      # Start the heartbeat service
      def start
        return unless @enabled
        return if @running

        @running = true
        arm_timer!

        Pocketrb.logger.info("Heartbeat service started (interval: #{@interval}s)")
      end

      # Stop the heartbeat service
      def stop
        @running = false
        @timer_thread&.kill
        @timer_thread = nil

        Pocketrb.logger.info("Heartbeat service stopped")
      end

      # Update the interval
      # @param seconds [Integer] New interval in seconds
      def set_interval(seconds)
        @mutex.synchronize { @interval = seconds }
        arm_timer! if @running
      end

      # Enable or disable the service
      # @param value [Boolean] Enabled state
      def enabled=(value)
        was_enabled = @enabled
        @enabled = value

        if @enabled && !was_enabled && @running
          arm_timer!
        elsif !@enabled && was_enabled
          @timer_thread&.kill
          @timer_thread = nil
        end
      end

      # Force a heartbeat check now
      # @return [String, nil] Response from agent or nil if skipped
      def tick
        @mutex.synchronize { @last_run_at = Time.now }

        content = read_heartbeat_file
        if empty_heartbeat?(content)
          Pocketrb.logger.debug("Heartbeat: no actionable content, skipping")
          return nil
        end

        Pocketrb.logger.info("Heartbeat: processing HEARTBEAT.md")

        begin
          response = @on_heartbeat.call(HEARTBEAT_PROMPT)

          if response&.include?("HEARTBEAT_OK")
            Pocketrb.logger.debug("Heartbeat: agent reports OK")
          else
            Pocketrb.logger.info("Heartbeat: agent processed tasks")
          end

          response
        rescue StandardError => e
          Pocketrb.logger.error("Heartbeat failed: #{e.message}")
          nil
        end
      end

      # Get status information
      # @return [Hash] Status info
      def status
        {
          enabled: @enabled,
          running: @running,
          interval: @interval,
          last_run_at: @last_run_at,
          heartbeat_file: heartbeat_file.to_s,
          file_exists: heartbeat_file.exist?,
          next_run_in: next_run_in
        }
      end

      private

      def arm_timer!
        return unless @running && @enabled

        @timer_thread&.kill
        @timer_thread = nil

        @timer_thread = Thread.new do
          loop do
            sleep @interval
            tick if @running && @enabled
          end
        end
      end

      def heartbeat_file
        @workspace.join(HEARTBEAT_FILE)
      end

      def read_heartbeat_file
        return nil unless heartbeat_file.exist?

        heartbeat_file.read
      rescue StandardError => e
        Pocketrb.logger.warn("Failed to read HEARTBEAT.md: #{e.message}")
        nil
      end

      def empty_heartbeat?(content)
        return true if content.nil? || content.strip.empty?

        # Skip if only contains:
        # - Empty lines
        # - Headers (# ...)
        # - HTML comments (<!-- ... -->)
        # - Unchecked checkboxes that are likely template (- [ ])
        # - Checked checkboxes (- [x])
        content.lines.all? do |line|
          stripped = line.strip
          stripped.empty? ||
            stripped.start_with?("#") ||
            stripped.start_with?("<!--") ||
            stripped.end_with?("-->") ||
            stripped.match?(/^- \[[xX ]\]\s*$/) # Empty checkbox
        end
      end

      def next_run_in
        return nil unless @running && @enabled && @last_run_at

        elapsed = Time.now - @last_run_at
        remaining = @interval - elapsed
        remaining.positive? ? remaining.to_i : 0
      end
    end
  end
end
