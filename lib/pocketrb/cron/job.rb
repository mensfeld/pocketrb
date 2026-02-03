# frozen_string_literal: true

module Pocketrb
  module Cron
    # Schedule types
    # - :at - one-time execution at specific timestamp
    # - :every - interval-based execution (every N seconds)
    # - :cron - cron expression-based execution
    Schedule = Data.define(:kind, :at_ms, :every_ms, :expr, :tz) do
      def initialize(kind:, at_ms: nil, every_ms: nil, expr: nil, tz: nil)
        super
      end

      def one_time?
        kind == :at
      end

      def interval?
        kind == :every
      end

      def cron?
        kind == :cron
      end
    end

    # Payload for job execution
    Payload = Data.define(:message, :deliver, :channel, :to) do
      def initialize(message:, deliver: false, channel: nil, to: nil)
        super
      end
    end

    # Job execution state
    JobState = Data.define(:next_run_at_ms, :last_run_at_ms, :last_status, :last_error) do
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

      def due?(now_ms = nil)
        return false unless enabled
        return false unless state.next_run_at_ms

        now_ms ||= (Time.now.to_f * 1000).to_i
        state.next_run_at_ms <= now_ms
      end

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
