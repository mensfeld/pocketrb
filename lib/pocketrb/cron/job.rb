# frozen_string_literal: true

module Pocketrb
  # Cron job scheduling system
  module Cron
    # Schedule types
    # - :at - one-time execution at specific timestamp
    # - :every - interval-based execution (every N seconds)
    # - :cron - cron expression-based execution
    Schedule = Data.define(:kind, :at_ms, :every_ms, :expr, :tz) do
      # Initialize schedule
      # @param kind [Symbol] Schedule type (:at, :every, or :cron)
      # @param at_ms [Integer, nil] Timestamp in milliseconds for one-time execution
      # @param every_ms [Integer, nil] Interval in milliseconds for recurring execution
      # @param expr [String, nil] Cron expression for cron-based scheduling
      # @param tz [String, nil] Timezone identifier (e.g., "America/New_York")
      def initialize(kind:, at_ms: nil, every_ms: nil, expr: nil, tz: nil)
        super
      end

      # Check if schedule is one-time execution
      # @return [Boolean] True if schedule type is :at
      def one_time?
        kind == :at
      end

      # Check if schedule is interval-based
      # @return [Boolean] True if schedule type is :every
      def interval?
        kind == :every
      end

      # Check if schedule is cron expression-based
      # @return [Boolean] True if schedule type is :cron
      def cron?
        kind == :cron
      end
    end

    # Payload for job execution
    Payload = Data.define(:message, :deliver, :channel, :to) do
      # Initialize payload
      # @param message [String] Content to send or task description when job executes
      # @param deliver [Boolean] Whether to deliver via messaging channel (defaults to false)
      # @param channel [Symbol, nil] Channel identifier for delivery (:telegram, :cli, etc.)
      # @param to [String, nil] Recipient identifier for channel delivery
      def initialize(message:, deliver: false, channel: nil, to: nil)
        super
      end
    end

    # Job execution state
    JobState = Data.define(:next_run_at_ms, :last_run_at_ms, :last_status, :last_error) do
      # Initialize job state
      # @param next_run_at_ms [Integer, nil] Timestamp in milliseconds for next scheduled run
      # @param last_run_at_ms [Integer, nil] Timestamp in milliseconds of last execution
      # @param last_status [String, nil] Status of last execution (success, failed, etc.)
      # @param last_error [String, nil] Error message from last failed execution
      def initialize(next_run_at_ms: nil, last_run_at_ms: nil, last_status: nil, last_error: nil)
        super
      end
    end

    # A scheduled cron job
    Job = Data.define(
      :id,
      :name,
      :enabled,
      :schedule,
      :payload,
      :state,
      :created_at_ms,
      :updated_at_ms,
      :delete_after_run
    ) do
      # Initialize cron job
      # @param id [String] Unique job identifier
      # @param name [String] Human-readable job name
      # @param schedule [Schedule] Job schedule configuration
      # @param payload [Payload] Job execution payload
      # @param enabled [Boolean] Whether job is enabled for execution (defaults to true)
      # @param state [JobState] Job execution state (defaults to new JobState)
      # @param created_at_ms [Integer, nil] Creation timestamp in milliseconds
      # @param updated_at_ms [Integer, nil] Last update timestamp in milliseconds
      # @param delete_after_run [Boolean] Whether to delete job after execution (defaults to false)
      def initialize(
        id:,
        name:,
        schedule:,
        payload:,
        enabled: true,
        state: JobState.new,
        created_at_ms: nil,
        updated_at_ms: nil,
        delete_after_run: false
      )
        super(
          id: id,
          name: name,
          enabled: enabled,
          schedule: schedule,
          payload: payload,
          state: state,
          created_at_ms: created_at_ms || (Time.now.to_f * 1000).to_i,
          updated_at_ms: updated_at_ms || (Time.now.to_f * 1000).to_i,
          delete_after_run: delete_after_run
        )
      end

      # Check if job is due to run
      # @param now_ms [Integer, nil] Current timestamp in milliseconds (defaults to Time.now)
      # @return [Boolean] True if job should execute now
      def due?(now_ms = nil)
        return false unless enabled
        return false unless state.next_run_at_ms

        now_ms ||= (Time.now.to_f * 1000).to_i
        state.next_run_at_ms <= now_ms
      end

      # Convert job to hash for serialization
      # @return [Hash] Job data as hash
      def to_h
        {
          "id" => id,
          "name" => name,
          "enabled" => enabled,
          "schedule" => {
            "kind" => schedule.kind.to_s,
            "at_ms" => schedule.at_ms,
            "every_ms" => schedule.every_ms,
            "expr" => schedule.expr,
            "tz" => schedule.tz
          },
          "payload" => {
            "message" => payload.message,
            "deliver" => payload.deliver,
            "channel" => payload.channel,
            "to" => payload.to
          },
          "state" => {
            "next_run_at_ms" => state.next_run_at_ms,
            "last_run_at_ms" => state.last_run_at_ms,
            "last_status" => state.last_status,
            "last_error" => state.last_error
          },
          "created_at_ms" => created_at_ms,
          "updated_at_ms" => updated_at_ms,
          "delete_after_run" => delete_after_run
        }
      end

      # Create job from hash representation
      # @param hash [Hash] Hash containing job data
      # @return [Job] New job instance
      def self.from_h(hash)
        schedule_h = hash["schedule"]
        schedule = Schedule.new(
          kind: schedule_h["kind"].to_sym,
          at_ms: schedule_h["at_ms"],
          every_ms: schedule_h["every_ms"],
          expr: schedule_h["expr"],
          tz: schedule_h["tz"]
        )

        payload_h = hash["payload"]
        payload = Payload.new(
          message: payload_h["message"],
          deliver: payload_h["deliver"],
          channel: payload_h["channel"],
          to: payload_h["to"]
        )

        state_h = hash["state"] || {}
        state = JobState.new(
          next_run_at_ms: state_h["next_run_at_ms"],
          last_run_at_ms: state_h["last_run_at_ms"],
          last_status: state_h["last_status"],
          last_error: state_h["last_error"]
        )

        Job.new(
          id: hash["id"],
          name: hash["name"],
          enabled: hash["enabled"],
          schedule: schedule,
          payload: payload,
          state: state,
          created_at_ms: hash["created_at_ms"],
          updated_at_ms: hash["updated_at_ms"],
          delete_after_run: hash["delete_after_run"]
        )
      end
    end
  end
end
