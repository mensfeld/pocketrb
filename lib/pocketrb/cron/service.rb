# frozen_string_literal: true

require "json"
require "securerandom"
require "fileutils"
require_relative "job"

module Pocketrb
  module Cron
    # Manages scheduled jobs with persistence and execution
    class Service
      attr_reader :jobs

      def initialize(store_path:, on_job:)
        @store_path = Pathname.new(store_path)
        @on_job = on_job
        @jobs = {}
        @mutex = Mutex.new
        @running = false
        @timer_thread = nil

        ensure_store_dir!
        load_jobs!
      end

      # Start the cron service
      def start
        return if @running

        @running = true
        compute_next_runs!
        arm_timer!

        Pocketrb.logger.info("Cron service started with #{@jobs.size} jobs")
      end

      # Stop the cron service
      def stop
        @running = false
        @timer_thread&.kill
        @timer_thread = nil

        Pocketrb.logger.info("Cron service stopped")
      end

      # List all jobs
      # @param include_disabled [Boolean] Include disabled jobs
      # @return [Array<Job>]
      def list_jobs(include_disabled: false)
        @mutex.synchronize do
          jobs = @jobs.values
          jobs = jobs.select(&:enabled) unless include_disabled
          jobs.sort_by { |j| j.state.next_run_at_ms || Float::INFINITY }
        end
      end

      # Add a new job
      # @param name [String] Job name
      # @param schedule [Schedule] Schedule configuration
      # @param message [String] Message to process
      # @param deliver [Boolean] Deliver to channel vs process as agent task
      # @param channel [String, nil] Target channel
      # @param to [String, nil] Target chat ID
      # @return [Job] Created job
      def add_job(name:, schedule:, message:, deliver: false, channel: nil, to: nil)
        job_id = SecureRandom.hex(8)

        payload = Payload.new(
          message: message,
          deliver: deliver,
          channel: channel,
          to: to
        )

        job = Job.new(
          id: job_id,
          name: name,
          schedule: schedule,
          payload: payload,
          delete_after_run: schedule.one_time?
        )

        job = compute_next_run(job)

        @mutex.synchronize do
          @jobs[job_id] = job
        end

        save_jobs!
        arm_timer!

        Pocketrb.logger.info("Added cron job '#{name}' (ID: #{job_id})")
        job
      end

      # Add a job with interval schedule
      # @param name [String] Job name
      # @param every [Integer] Interval in seconds
      # @param message [String] Message to process
      # @param deliver [Boolean] Deliver to channel
      # @param channel [String, nil] Target channel
      # @param to [String, nil] Target chat ID
      # @return [Job]
      def add_interval_job(name:, every:, message:, deliver: false, channel: nil, to: nil)
        schedule = Pocketrb::Cron::Schedule.new(kind: :every, every_ms: every * 1000)
        add_job(name: name, schedule: schedule, message: message, deliver: deliver, channel: channel, to: to)
      end

      # Add a job with cron expression
      # @param name [String] Job name
      # @param cron [String] Cron expression
      # @param message [String] Message to process
      # @param tz [String, nil] Timezone
      # @param deliver [Boolean] Deliver to channel
      # @param channel [String, nil] Target channel
      # @param to [String, nil] Target chat ID
      # @return [Job]
      def add_cron_job(name:, cron:, message:, tz: nil, deliver: false, channel: nil, to: nil)
        schedule = Pocketrb::Cron::Schedule.new(kind: :cron, expr: cron, tz: tz)
        add_job(name: name, schedule: schedule, message: message, deliver: deliver, channel: channel, to: to)
      end

      # Add a one-time job
      # @param name [String] Job name
      # @param at [Time, Integer] Execution time (Time or Unix timestamp)
      # @param message [String] Message to process
      # @param deliver [Boolean] Deliver to channel
      # @param channel [String, nil] Target channel
      # @param to [String, nil] Target chat ID
      # @return [Job]
      def add_one_time_job(name:, at:, message:, deliver: false, channel: nil, to: nil)
        at_ms = at.is_a?(Time) ? (at.to_f * 1000).to_i : at * 1000
        schedule = Pocketrb::Cron::Schedule.new(kind: :at, at_ms: at_ms)
        add_job(name: name, schedule: schedule, message: message, deliver: deliver, channel: channel, to: to)
      end

      # Remove a job
      # @param job_id [String] Job ID
      # @return [Boolean] Whether job was removed
      def remove_job(job_id)
        removed = @mutex.synchronize do
          @jobs.delete(job_id)
        end

        if removed
          save_jobs!
          arm_timer!
          Pocketrb.logger.info("Removed cron job #{job_id}")
          true
        else
          false
        end
      end

      # Enable or disable a job
      # @param job_id [String] Job ID
      # @param enabled [Boolean] Enabled state
      # @return [Job, nil] Updated job
      def enable_job(job_id, enabled: true)
        job = @mutex.synchronize do
          current = @jobs[job_id]
          return nil unless current

          updated = Job.new(
            id: current.id,
            name: current.name,
            enabled: enabled,
            schedule: current.schedule,
            payload: current.payload,
            state: current.state,
            created_at_ms: current.created_at_ms,
            updated_at_ms: (Time.now.to_f * 1000).to_i,
            delete_after_run: current.delete_after_run
          )

          @jobs[job_id] = updated
          updated
        end

        save_jobs!
        arm_timer!
        job
      end

      # Run a job manually (force execution)
      # @param job_id [String] Job ID
      # @param force [Boolean] Run even if disabled
      # @return [Boolean] Whether job was executed
      def run_job(job_id, force: false)
        job = @mutex.synchronize { @jobs[job_id] }
        return false unless job
        return false unless force || job.enabled

        execute_job(job)
        true
      end

      # Get a job by ID
      # @param job_id [String] Job ID
      # @return [Job, nil]
      def get_job(job_id)
        @mutex.synchronize { @jobs[job_id] }
      end

      private

      def ensure_store_dir!
        FileUtils.mkdir_p(@store_path.dirname)
      end

      def load_jobs!
        return unless @store_path.exist?

        data = JSON.parse(File.read(@store_path))
        @jobs = data.transform_values { |h| Job.from_h(h) }
        Pocketrb.logger.debug("Loaded #{@jobs.size} cron jobs")
      rescue JSON::ParserError => e
        Pocketrb.logger.warn("Failed to parse cron jobs: #{e.message}")
        @jobs = {}
      end

      def save_jobs!
        @mutex.synchronize do
          data = @jobs.transform_values(&:to_h)
          File.write(@store_path, JSON.pretty_generate(data))
        end
      end

      def compute_next_runs!
        now_ms = (Time.now.to_f * 1000).to_i

        @mutex.synchronize do
          @jobs.each do |id, job|
            next unless job.enabled
            next if job.state.next_run_at_ms && job.state.next_run_at_ms > now_ms

            @jobs[id] = compute_next_run(job)
          end
        end

        save_jobs!
      end

      def compute_next_run(job)
        now_ms = (Time.now.to_f * 1000).to_i
        next_ms = case job.schedule.kind
                  when :at
                    job.schedule.at_ms
                  when :every
                    base = job.state.last_run_at_ms || now_ms
                    base + job.schedule.every_ms
                  when :cron
                    compute_cron_next(job.schedule.expr, job.schedule.tz)
                  end

        new_state = JobState.new(
          next_run_at_ms: next_ms,
          last_run_at_ms: job.state.last_run_at_ms,
          last_status: job.state.last_status,
          last_error: job.state.last_error
        )

        Job.new(
          id: job.id,
          name: job.name,
          enabled: job.enabled,
          schedule: job.schedule,
          payload: job.payload,
          state: new_state,
          created_at_ms: job.created_at_ms,
          updated_at_ms: job.updated_at_ms,
          delete_after_run: job.delete_after_run
        )
      end

      def compute_cron_next(expr, tz = nil)
        # Try to use fugit if available

        require "fugit"
        cron = Fugit.parse_cron(expr)
        return nil unless cron

        now = Time.now
        now = now.in_time_zone(tz) if tz && now.respond_to?(:in_time_zone)

        next_time = cron.next_time(now)
        (next_time.to_f * 1000).to_i
      rescue LoadError
        # Fallback: simple minute-based scheduling without fugit
        Pocketrb.logger.warn("Fugit gem not available, cron expressions may not work correctly")
        ((Time.now.to_f * 1000) + 60_000).to_i
      end

      def arm_timer!
        return unless @running

        @timer_thread&.kill
        @timer_thread = nil

        # Find earliest next run
        earliest = @mutex.synchronize do
          @jobs.values
               .select(&:enabled)
               .filter_map { |j| j.state.next_run_at_ms }
               .min
        end

        return unless earliest

        now_ms = (Time.now.to_f * 1000).to_i
        delay_ms = [earliest - now_ms, 0].max
        delay_s = delay_ms / 1000.0

        @timer_thread = Thread.new do
          sleep delay_s
          tick if @running
        end

        Pocketrb.logger.debug("Cron timer armed for #{delay_s}s")
      end

      def tick
        now_ms = (Time.now.to_f * 1000).to_i
        due_jobs = @mutex.synchronize do
          @jobs.values.select { |j| j.due?(now_ms) }
        end

        due_jobs.each do |job|
          execute_job(job)
        end

        arm_timer!
      end

      def execute_job(job)
        Pocketrb.logger.info("Executing cron job '#{job.name}' (ID: #{job.id})")

        begin
          @on_job.call(job)

          update_job_state(job.id, status: "success")

          if job.delete_after_run
            remove_job(job.id)
          else
            update_job_next_run(job.id)
          end
        rescue StandardError => e
          Pocketrb.logger.error("Cron job #{job.id} failed: #{e.message}")
          update_job_state(job.id, status: "failed", error: e.message)
          update_job_next_run(job.id) unless job.delete_after_run
        end
      end

      def update_job_state(job_id, status:, error: nil)
        @mutex.synchronize do
          job = @jobs[job_id]
          return unless job

          new_state = JobState.new(
            next_run_at_ms: job.state.next_run_at_ms,
            last_run_at_ms: (Time.now.to_f * 1000).to_i,
            last_status: status,
            last_error: error
          )

          @jobs[job_id] = Job.new(
            id: job.id,
            name: job.name,
            enabled: job.enabled,
            schedule: job.schedule,
            payload: job.payload,
            state: new_state,
            created_at_ms: job.created_at_ms,
            updated_at_ms: (Time.now.to_f * 1000).to_i,
            delete_after_run: job.delete_after_run
          )
        end

        save_jobs!
      end

      def update_job_next_run(job_id)
        @mutex.synchronize do
          job = @jobs[job_id]
          return unless job

          @jobs[job_id] = compute_next_run(job)
        end

        save_jobs!
      end
    end
  end
end
