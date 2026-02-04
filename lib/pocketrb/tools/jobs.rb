# frozen_string_literal: true

module Pocketrb
  module Tools
    # Manage background jobs
    class Jobs < Base
      def name
        "jobs"
      end

      def description
        "Manage background jobs. List running/completed jobs, get output, or kill jobs."
      end

      def parameters
        {
          type: "object",
          properties: {
            action: {
              type: "string",
              enum: %w[list status output kill],
              description: "Action: list (all jobs), status (job details), output (job logs), kill (stop job)"
            },
            job_id: {
              type: "string",
              description: "Job ID (required for status, output, kill)"
            },
            lines: {
              type: "integer",
              description: "Number of output lines to show (default: 50)"
            }
          },
          required: ["action"]
        }
      end

      def execute(action:, job_id: nil, lines: 50)
        case action
        when "list"
          list_jobs
        when "status"
          get_status(job_id)
        when "output"
          get_output(job_id, lines)
        when "kill"
          kill_job(job_id)
        else
          error("Unknown action: #{action}")
        end
      end

      private

      def job_manager
        # Use memory_dir for job storage (falls back to workspace if not set)
        storage_dir = @context[:memory_dir] || workspace
        @job_manager ||= BackgroundJobManager.new(workspace: storage_dir)
      end

      def list_jobs
        jobs = job_manager.list

        return "No background jobs found." if jobs.empty?

        output = ["Background Jobs:\n"]

        running = jobs.select { |j| j[:running] }
        completed = jobs.reject { |j| j[:running] }

        if running.any?
          output << "RUNNING:"
          running.each do |job|
            output << "  [#{job[:job_id]}] PID #{job[:pid]} - #{job[:name]}"
          end
          output << ""
        end

        if completed.any?
          output << "COMPLETED:"
          completed.first(10).each do |job|
            output << "  [#{job[:job_id]}] - #{job[:name]}"
          end
          output << "  ... and #{completed.length - 10} more" if completed.length > 10
        end

        output.join("\n")
      end

      def get_status(job_id)
        return error("Job ID required") unless job_id

        status = job_manager.status(job_id)
        return error("Job not found: #{job_id}") unless status

        <<~STATUS
          Job: #{status[:job_id]}
          Name: #{status[:name]}
          Status: #{status[:running] ? "RUNNING" : "COMPLETED"}
          PID: #{status[:pid]}
          Command: #{status[:command]}

          Recent output:
          #{status[:output].lines.last(20).join}
        STATUS
      end

      def get_output(job_id, lines)
        return error("Job ID required") unless job_id

        output = job_manager.output(job_id, lines: lines)
        return error("Job not found: #{job_id}") unless output

        "Output (last #{lines} lines):\n#{output}"
      end

      def kill_job(job_id)
        return error("Job ID required") unless job_id

        if job_manager.kill(job_id)
          success("Killed job: #{job_id}")
        else
          error("Could not kill job: #{job_id} (may not be running)")
        end
      end
    end
  end
end
