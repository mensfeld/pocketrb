# frozen_string_literal: true

require "open3"

module Pocketrb
  module Tools
    # Manages background jobs for long-running commands
    class BackgroundJobManager
      MAX_JOBS = 50
      MAX_COMPLETED_JOBS = 20
      MAX_JOB_AGE = 24 * 60 * 60 # 24 hours

      # Commands that should auto-run in background
      LONG_RUNNING_PATTERNS = [
        /^apt(-get)?\s+(install|update|upgrade|dist-upgrade|autoremove)/i,
        /^(npm|yarn|pnpm)\s+(install|ci|update|build|run\s+build)/i,
        /^pip3?\s+install/i,
        /^gem\s+install/i,
        /^bundle\s+(install|update)/i,
        /^cargo\s+(build|install|run)/i,
        /^make\b/i,
        /^docker\s+(build|pull|push|run)/i,
        /^wget\s/i,
        /^git\s+(clone|pull|fetch)/i,
        /sleep\s+\d{2,}/, # sleep 10+ seconds
        /^python3?\s+.*\.py/i,
        /^ruby\s+.*\.rb/i,
        /^node\s+.*\.js/i,
        /nohup\s/i,
        /&\s*$/ # ends with &
      ].freeze

      attr_reader :jobs_dir

      def initialize(workspace:)
        @workspace = Pathname.new(workspace)
        @jobs_dir = resolve_jobs_dir
        FileUtils.mkdir_p(@jobs_dir)
        cleanup_stale_jobs
      end

      private

      def resolve_jobs_dir
        # Don't create .pocketrb in root filesystem
        if @workspace.to_s == "/" || !@workspace.writable?
          Pathname.new(Dir.home).join(".pocketrb", "jobs")
        else
          @workspace.join(".pocketrb", "jobs")
        end
      end

      public

      # Check if command should auto-run in background
      def long_running?(command)
        return false if command.nil? || command.empty?

        LONG_RUNNING_PATTERNS.any? { |pattern| command.match?(pattern) }
      end

      # Start a background job
      def start(command:, working_dir: nil, name: nil)
        cleanup_stale_jobs

        job_id = "job_#{Time.now.to_i}_#{rand(10_000)}"
        job_dir = @jobs_dir.join(job_id)
        FileUtils.mkdir_p(job_dir)

        log_file = job_dir.join("output.log")
        pid_file = job_dir.join("pid")
        cmd_file = job_dir.join("command")
        name_file = job_dir.join("name")
        status_file = job_dir.join("status")

        File.write(cmd_file, command)
        File.write(name_file, name || command[0..50])
        File.write(status_file, "running")

        work_dir = working_dir || @workspace.to_s

        pid = Process.spawn(
          "bash", "-lc", command,
          chdir: work_dir,
          out: [log_file.to_s, "a"],
          err: [log_file.to_s, "a"],
          pgroup: true
        )
        Process.detach(pid)

        File.write(pid_file, pid.to_s)

        {
          job_id: job_id,
          pid: pid,
          log_file: log_file.to_s
        }
      end

      # List all jobs
      def list
        return [] unless @jobs_dir.exist?

        Dir.glob(@jobs_dir.join("job_*")).filter_map do |job_dir|
          job_id = File.basename(job_dir)
          job_dir_path = Pathname.new(job_dir)

          pid_file = job_dir_path.join("pid")
          name_file = job_dir_path.join("name")

          next unless pid_file.exist?

          pid = File.read(pid_file).strip.to_i
          name = name_file.exist? ? File.read(name_file).strip : "unknown"
          running = process_running?(pid)

          {
            job_id: job_id,
            pid: pid,
            name: name,
            running: running,
            created_at: File.mtime(job_dir)
          }
        end.sort_by { |j| j[:created_at] }.reverse
      end

      # Get job status and output
      def status(job_id)
        job_dir = @jobs_dir.join(job_id)
        return nil unless job_dir.exist?

        pid_file = job_dir.join("pid")
        log_file = job_dir.join("output.log")
        cmd_file = job_dir.join("command")
        name_file = job_dir.join("name")

        pid = pid_file.exist? ? File.read(pid_file).strip.to_i : nil
        running = pid ? process_running?(pid) : false
        output = log_file.exist? ? truncate_output(File.read(log_file)) : ""
        command = cmd_file.exist? ? File.read(cmd_file) : "unknown"
        name = name_file.exist? ? File.read(name_file).strip : "unknown"

        {
          job_id: job_id,
          pid: pid,
          name: name,
          running: running,
          output: output,
          command: command
        }
      end

      # Get job output (tail)
      def output(job_id, lines: 50)
        log_file = @jobs_dir.join(job_id, "output.log")
        return nil unless log_file.exist?

        `tail -n #{lines} #{log_file}`
      end

      # Kill a job
      def kill(job_id)
        pid_file = @jobs_dir.join(job_id, "pid")
        return false unless pid_file.exist?

        pid = File.read(pid_file).strip.to_i
        return false unless process_running?(pid)

        begin
          Process.kill("-TERM", pid)
          sleep 0.5
          Process.kill("-KILL", pid) if process_running?(pid)

          status_file = @jobs_dir.join(job_id, "status")
          File.write(status_file, "killed")
          true
        rescue Errno::ESRCH
          false
        end
      end

      # Clean up old jobs
      def cleanup_stale_jobs
        return 0 unless @jobs_dir.exist?

        jobs = Dir.glob(@jobs_dir.join("job_*")).filter_map do |job_dir|
          pid_file = File.join(job_dir, "pid")
          next nil unless File.exist?(pid_file)

          pid = begin
            File.read(pid_file).strip.to_i
          rescue StandardError
            0
          end
          running = pid.positive? && process_running?(pid)
          created = begin
            File.mtime(job_dir)
          rescue StandardError
            Time.now
          end

          { dir: job_dir, running: running, created: created }
        end

        completed_jobs = jobs.reject { |j| j[:running] }.sort_by { |j| j[:created] }
        removed = 0

        # Remove jobs older than MAX_JOB_AGE
        cutoff = Time.now - MAX_JOB_AGE
        completed_jobs.each do |job|
          if job[:created] < cutoff
            FileUtils.rm_rf(job[:dir])
            removed += 1
          end
        end

        completed_jobs.reject! { |j| j[:created] < cutoff }

        # Keep only MAX_COMPLETED_JOBS
        while completed_jobs.length > MAX_COMPLETED_JOBS
          oldest = completed_jobs.shift
          FileUtils.rm_rf(oldest[:dir])
          removed += 1
        end

        removed
      rescue StandardError => e
        Pocketrb.logger.warn("Job cleanup error: #{e.message}")
        0
      end

      private

      def process_running?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH, Errno::EPERM
        false
      end

      def truncate_output(output, max_size: 100_000)
        return output if output.length <= max_size

        "#{output[0...max_size]}\n... (truncated, #{output.length - max_size} more characters)"
      end
    end
  end
end
