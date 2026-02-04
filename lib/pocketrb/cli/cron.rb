# frozen_string_literal: true

module Pocketrb
  class CLI
    # Cron command - manages scheduled jobs
    class Cron < Thor
      desc "list", "List scheduled jobs"
      option :all, type: :boolean, aliases: "-a", desc: "Include disabled jobs"
      def list
        workspace = Pathname.new(options[:workspace] || Dir.pwd).expand_path
        cron_store = workspace.join(".pocketrb", "data", "cron", "jobs.json")

        service = Pocketrb::Cron::Service.new(
          store_path: cron_store,
          on_job: ->(_) {}
        )

        jobs = service.list_jobs(include_disabled: options[:all])
        if jobs.empty?
          say "No scheduled jobs", :yellow
          return
        end

        say "Scheduled jobs:"
        jobs.each do |job|
          status = job.enabled ? "enabled" : "disabled"
          next_run = job.state.next_run_at_ms ? Time.at(job.state.next_run_at_ms / 1000).strftime("%Y-%m-%d %H:%M") : "never"
          say "  #{job.id}: #{job.name} [#{status}] - next: #{next_run}"
        end
      end

      desc "add", "Add a scheduled job"
      option :name, type: :string, required: true, desc: "Job name"
      option :message, type: :string, required: true, desc: "Message to process"
      option :every, type: :numeric, desc: "Run every N seconds"
      option :cron, type: :string, desc: "Cron expression (e.g., '0 9 * * *')"
      option :at, type: :string, desc: "Run once at ISO datetime"
      option :deliver, type: :boolean, default: false, desc: "Deliver to channel instead of processing"
      option :channel, type: :string, desc: "Target channel for delivery"
      option :to, type: :string, desc: "Target chat ID for delivery"
      def add
        workspace = Pathname.new(options[:workspace] || Dir.pwd).expand_path
        cron_store = workspace.join(".pocketrb", "data", "cron", "jobs.json")

        service = Pocketrb::Cron::Service.new(
          store_path: cron_store,
          on_job: ->(_) {}
        )

        job = if options[:every]
                service.add_interval_job(
                  name: options[:name],
                  every: options[:every],
                  message: options[:message],
                  deliver: options[:deliver],
                  channel: options[:channel],
                  to: options[:to]
                )
              elsif options[:cron]
                service.add_cron_job(
                  name: options[:name],
                  cron: options[:cron],
                  message: options[:message],
                  deliver: options[:deliver],
                  channel: options[:channel],
                  to: options[:to]
                )
              elsif options[:at]
                at_time = Time.parse(options[:at])
                service.add_one_time_job(
                  name: options[:name],
                  at: at_time,
                  message: options[:message],
                  deliver: options[:deliver],
                  channel: options[:channel],
                  to: options[:to]
                )
              else
                say "Error: Must specify --every, --cron, or --at", :red
                exit 1
              end

        say "Created job: #{job.id} (#{job.name})", :green
      end

      desc "remove JOB_ID", "Remove a scheduled job"
      def remove(job_id)
        workspace = Pathname.new(options[:workspace] || Dir.pwd).expand_path
        cron_store = workspace.join(".pocketrb", "data", "cron", "jobs.json")

        service = Pocketrb::Cron::Service.new(
          store_path: cron_store,
          on_job: ->(_) {}
        )

        if service.remove_job(job_id)
          say "Removed job: #{job_id}", :green
        else
          say "Job not found: #{job_id}", :red
        end
      end

      desc "enable JOB_ID", "Enable a scheduled job"
      def enable(job_id)
        workspace = Pathname.new(options[:workspace] || Dir.pwd).expand_path
        cron_store = workspace.join(".pocketrb", "data", "cron", "jobs.json")

        service = Pocketrb::Cron::Service.new(
          store_path: cron_store,
          on_job: ->(_) {}
        )

        if service.enable_job(job_id, enabled: true)
          say "Enabled job: #{job_id}", :green
        else
          say "Job not found: #{job_id}", :red
        end
      end

      desc "disable JOB_ID", "Disable a scheduled job"
      def disable(job_id)
        workspace = Pathname.new(options[:workspace] || Dir.pwd).expand_path
        cron_store = workspace.join(".pocketrb", "data", "cron", "jobs.json")

        service = Pocketrb::Cron::Service.new(
          store_path: cron_store,
          on_job: ->(_) {}
        )

        if service.enable_job(job_id, enabled: false)
          say "Disabled job: #{job_id}", :green
        else
          say "Job not found: #{job_id}", :red
        end
      end

      desc "trigger JOB_ID", "Trigger a job manually"
      def trigger(_job_id)
        say "Manual job execution requires running gateway", :yellow
        say "Use 'pocketrb gateway' and the job will be executed", :yellow
      end
    end
  end
end
