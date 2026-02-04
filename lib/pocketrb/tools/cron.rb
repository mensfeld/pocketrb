# frozen_string_literal: true

require "time"

module Pocketrb
  module Tools
    # Manage scheduled cron jobs - allows agent to be proactive
    class Cron < Base
      def name
        "cron"
      end

      def description
        <<~DESC.strip
          Manage scheduled tasks. Create reminders, follow-ups, or recurring checks.
          Use this to be proactive - schedule nudges, daily check-ins, or one-time reminders.
        DESC
      end

      def parameters
        {
          type: "object",
          properties: {
            action: {
              type: "string",
              enum: %w[add list remove enable disable],
              description: "Action: add (new job), list (show jobs), remove/enable/disable (manage job)"
            },
            name: {
              type: "string",
              description: "Job name/label (required for add)"
            },
            message: {
              type: "string",
              description: "Message to send when job runs (required for add)"
            },
            schedule_type: {
              type: "string",
              enum: %w[at every cron],
              description: "Schedule type: 'at' (one-time), 'every' (interval), 'cron' (expression)"
            },
            schedule_value: {
              type: "string",
              description: "Schedule value: ISO datetime for 'at', seconds for 'every', cron expr for 'cron'"
            },
            job_id: {
              type: "string",
              description: "Job ID (required for remove/enable/disable)"
            },
            deliver: {
              type: "boolean",
              description: "If true, deliver message to channel. If false, just wake agent with message."
            }
          },
          required: ["action"]
        }
      end

      def available?
        !cron_service.nil?
      end

      def execute(action:, name: nil, message: nil, schedule_type: nil, schedule_value: nil, job_id: nil, deliver: true)
        return error("Cron service not available. Start with --enable-cron flag.") unless cron_service

        case action
        when "add"
          add_job(name, message, schedule_type, schedule_value, deliver)
        when "list"
          list_jobs
        when "remove"
          remove_job(job_id)
        when "enable"
          toggle_job(job_id, true)
        when "disable"
          toggle_job(job_id, false)
        else
          error("Unknown action: #{action}")
        end
      end

      private

      def cron_service
        @context[:cron_service]
      end

      def current_channel
        @context[:default_channel] || @context[:channel] || :telegram
      end

      def current_chat_id
        @context[:default_chat_id] || @context[:chat_id]
      end

      def add_job(name, message, schedule_type, schedule_value, deliver)
        return error("Name required") unless name && !name.empty?
        return error("Message required") unless message && !message.empty?
        return error("Schedule type required (at, every, or cron)") unless schedule_type

        schedule = build_schedule(schedule_type, schedule_value)
        return schedule if schedule.is_a?(String) && schedule.start_with?("Error")

        job = cron_service.add_job(
          name: name,
          schedule: schedule,
          message: message,
          deliver: deliver,
          channel: current_channel.to_s,
          to: current_chat_id
        )

        next_run = job.state.next_run_at_ms
        next_run_time = Time.at(next_run / 1000).strftime("%Y-%m-%d %H:%M:%S") if next_run

        success("Created job '#{name}' (ID: #{job.id}). Next run: #{next_run_time || "pending"}")
      end

      def build_schedule(type, value)
        case type
        when "at"
          # One-time: parse ISO datetime
          return error("Datetime required for 'at' schedule") unless value

          begin
            time = Time.parse(value)
            return error("Scheduled time must be in the future") if time <= Time.now

            ::Pocketrb::Cron::Schedule.new(kind: :at, at_ms: (time.to_f * 1000).to_i)
          rescue ArgumentError => e
            error("Invalid datetime: #{e.message}. Use ISO format like '2026-02-04T09:00:00'")
          end

        when "every"
          # Interval: parse seconds
          return error("Interval in seconds required for 'every' schedule") unless value

          seconds = value.to_i
          return error("Interval must be at least 60 seconds") if seconds < 60

          ::Pocketrb::Cron::Schedule.new(kind: :every, every_ms: seconds * 1000)

        when "cron"
          # Cron expression
          return error("Cron expression required") unless value

          ::Pocketrb::Cron::Schedule.new(kind: :cron, expr: value)

        else
          error("Unknown schedule type: #{type}")
        end
      end

      def list_jobs
        jobs = cron_service.list_jobs(include_disabled: true)

        return "No scheduled jobs." if jobs.empty?

        lines = ["Scheduled Jobs:\n"]

        jobs.each do |job|
          status = job.enabled ? "✓" : "✗"
          next_run = if job.state.next_run_at_ms
                       Time.at(job.state.next_run_at_ms / 1000).strftime("%m/%d %H:%M")
                     else
                       "—"
                     end

          schedule_desc = format_schedule(job.schedule)
          lines << "#{status} [#{job.id}] #{job.name}"
          lines << "    Schedule: #{schedule_desc}"
          lines << "    Next: #{next_run}"
          lines << "    Message: #{job.payload.message[0..50]}#{"..." if job.payload.message.length > 50}"
          lines << ""
        end

        lines.join("\n")
      end

      def format_schedule(schedule)
        case schedule.kind
        when :at
          time = Time.at(schedule.at_ms / 1000)
          "One-time at #{time.strftime("%Y-%m-%d %H:%M")}"
        when :every
          seconds = schedule.every_ms / 1000
          if seconds >= 86_400
            "Every #{seconds / 86_400} day(s)"
          elsif seconds >= 3600
            "Every #{seconds / 3600} hour(s)"
          else
            "Every #{seconds / 60} minute(s)"
          end
        when :cron
          "Cron: #{schedule.expr}"
        else
          "Unknown"
        end
      end

      def remove_job(job_id)
        return error("Job ID required") unless job_id

        if cron_service.remove_job(job_id)
          success("Removed job: #{job_id}")
        else
          error("Job not found: #{job_id}")
        end
      end

      def toggle_job(job_id, enabled)
        return error("Job ID required") unless job_id

        if cron_service.enable_job(job_id, enabled: enabled)
          success("Job #{job_id} #{enabled ? "enabled" : "disabled"}")
        else
          error("Job not found: #{job_id}")
        end
      end
    end
  end
end
