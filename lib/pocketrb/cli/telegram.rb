# frozen_string_literal: true

module Pocketrb
  class CLI
    # Telegram command - runs agent as a Telegram bot
    class Telegram < Base
      desc "telegram", "Run as a Telegram bot"
      option :model, type: :string, aliases: "-m", desc: "Model to use"
      option :provider, type: :string, aliases: "-p", desc: "LLM provider"
      option :token, type: :string, aliases: "-t", desc: "Telegram bot token (or TELEGRAM_BOT_TOKEN env)"
      option :allowed_users, type: :array, aliases: "-u", desc: "Allowed usernames or user IDs"
      option :enable_cron, type: :boolean, default: true, desc: "Enable cron/scheduling service"
      option :autonomous, type: :boolean, default: false, desc: "Skip permission prompts (for sandboxed environments)"

      # Runs the agent as a Telegram bot
      # @return [void]
      def call
        setup_logging
        workspace = resolve_workspace
        memory_dir = resolve_memory_dir

        token = options[:token] || ENV.fetch("TELEGRAM_BOT_TOKEN", nil)
        unless token
          say "Error: Telegram bot token required", :red
          say "Set TELEGRAM_BOT_TOKEN env var or use --token", :yellow
          exit 1
        end

        config = Pocketrb::Config.load(memory_dir)
        config[:model] = options[:model] if options[:model]
        config[:provider] = options[:provider] if options[:provider]
        config[:autonomous] = options[:autonomous] if options[:autonomous]

        provider = create_provider(config)
        bus = Pocketrb::Bus::MessageBus.new

        agent_loop = Pocketrb::Agent::Loop.new(
          bus: bus,
          provider: provider,
          workspace: workspace,
          memory_dir: memory_dir,
          model: config[:model],
          max_iterations: config[:max_iterations]
        )

        # Enable cron service for proactive scheduling
        cron_service = nil
        if options[:enable_cron]
          cron_store = memory_dir.join(".pocketrb", "data", "cron", "jobs.json")
          cron_service = Pocketrb::Cron::Service.new(
            store_path: cron_store,
            on_job: ->(job) { handle_cron_job(agent_loop, bus, job) }
          )
          agent_loop.tools.update_context(cron_service: cron_service)
        end

        say "Starting Pocketrb Telegram Bot", :green
        say "Provider: #{config[:provider]}/#{config[:model]}"
        say "Workspace: #{workspace}"
        say "Memory: #{memory_dir}" if memory_dir != workspace
        say "Cron: #{options[:enable_cron] ? "enabled" : "disabled"}"
        say "Autonomous: #{options[:autonomous] ? "yes (claude_cli only)" : "no"}" if options[:autonomous]
        say "Press Ctrl+C to stop\n"

        channel = Pocketrb::Channels::Telegram.new(
          bus: bus,
          token: token,
          allowed_users: options[:allowed_users]
        )

        # Set up status context for /status command
        channel.status_context = {
          provider: provider,
          model: config[:model],
          sessions: agent_loop.sessions,
          memory_dir: memory_dir,
          cron_service: cron_service
        }

        Async do
          agent_loop.run
          channel.run
          cron_service&.start
        end
      rescue Interrupt
        say "\nShutting down Telegram bot...", :yellow
        cron_service&.stop
      end

      default_task :call
    end
  end
end
