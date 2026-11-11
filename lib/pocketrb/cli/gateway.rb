# frozen_string_literal: true

module Pocketrb
  class CLI
    # Gateway command - starts all services together
    class Gateway < Base
      desc "gateway", "Start the gateway with all services"
      option :model, type: :string, aliases: "-m", desc: "Model to use"
      option :provider, type: :string, aliases: "-p", desc: "LLM provider"
      option :telegram_token, type: :string, desc: "Telegram bot token"
      option :telegram_users, type: :array, desc: "Allowed Telegram users"
      option :whatsapp_bridge, type: :string, desc: "WhatsApp bridge URL (default: ws://localhost:3001)"
      option :whatsapp_users, type: :array, desc: "Allowed WhatsApp numbers"
      option :heartbeat_interval, type: :numeric, default: 1800, desc: "Heartbeat interval in seconds"
      option :enable_cron, type: :boolean, default: true, desc: "Enable cron service"
      option :enable_heartbeat, type: :boolean, default: true, desc: "Enable heartbeat service"
      option :autonomous, type: :boolean, default: false, desc: "Skip permission prompts (for sandboxed environments)"

      # Starts the gateway with all configured services (Telegram, WhatsApp, cron, heartbeat)
      # @return [void]
      def call
        setup_logging
        workspace = resolve_workspace
        memory_dir = resolve_memory_dir

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

        say "Starting Pocketrb Gateway", :green
        say "Provider: #{config[:provider]}/#{config[:model]}"
        say "Workspace: #{workspace}"
        say "Memory: #{memory_dir}" if memory_dir != workspace

        channels = []
        services = []
        cron_service = nil

        # Start Telegram if token provided
        telegram_token = options[:telegram_token] || ENV.fetch("TELEGRAM_BOT_TOKEN", nil)
        if telegram_token
          channels << Pocketrb::Channels::Telegram.new(
            bus: bus,
            token: telegram_token,
            allowed_users: options[:telegram_users]
          )
          say "  - Telegram: enabled"
        end

        # Start WhatsApp; an explicit --whatsapp-bridge requires websocket-client-simple
        bridge_url = options[:whatsapp_bridge] || Pocketrb::Channels::WhatsApp::DEFAULT_BRIDGE_URL
        whatsapp = Pocketrb::Channels::WhatsApp.new(
          bus: bus,
          bridge_url: bridge_url,
          allowed_users: options[:whatsapp_users]
        )
        if options[:whatsapp_bridge] || whatsapp.available?
          whatsapp.ensure_available!
          channels << whatsapp
          say "  - WhatsApp: enabled (#{bridge_url})"
        else
          say "  - WhatsApp: skipped (websocket-client-simple gem not installed)", :yellow
        end

        # Start Cron service
        if options[:enable_cron]
          cron_store = memory_dir.join(".pocketrb", "data", "cron", "jobs.json")
          cron_service = Pocketrb::Cron::Service.new(
            store_path: cron_store,
            on_job: ->(job) { handle_cron_job(agent_loop, bus, job) }
          )
          services << cron_service
          # Pass cron_service to tools so agent can manage jobs
          agent_loop.tools.update_context(cron_service: cron_service)
          say "  - Cron: enabled"
        end

        # Start Heartbeat service
        if options[:enable_heartbeat]
          heartbeat_service = Pocketrb::Heartbeat::Service.new(
            workspace: workspace,
            interval: options[:heartbeat_interval],
            on_heartbeat: ->(prompt) { process_heartbeat(agent_loop, prompt) }
          )
          services << heartbeat_service
          say "  - Heartbeat: enabled (#{options[:heartbeat_interval]}s)"
        end

        # Set up status context for /status command on Telegram channels
        status_context = {
          provider: provider,
          model: config[:model],
          sessions: agent_loop.sessions,
          memory_dir: memory_dir,
          cron_service: cron_service
        }
        channels.each do |ch|
          ch.status_context = status_context if ch.respond_to?(:status_context=)
        end

        say "\nPress Ctrl+C to stop\n"

        Async do |task|
          # Start agent loop
          agent_loop.run

          # Start all channels, each in its own task so a blocking channel does not hold back the rest
          channels.each do |channel|
            task.async { run_channel(channel) }
          end

          # Channels have claimed their messages; drop the rest so they do not pile up
          task.async { drop_unrouted_outbound(bus) }

          # Start all services
          services.each(&:start)

          # Keep running
          sleep
        end
      rescue Interrupt
        say "\nShutting down gateway...", :yellow
        channels&.each(&:stop)
        services&.each(&:stop)
        agent_loop&.stop
      end

      private

      # Runs a channel and logs its failure, so one failing channel does not stop the others
      # @param channel [Channels::Base] Telegram or WhatsApp channel started by the gateway
      # @return [void]
      def run_channel(channel)
        channel.run
      rescue StandardError => e
        Pocketrb.logger.error("#{channel.name} channel stopped: #{e.message}")
      end

      # Drops outbound messages left in the shared queue, which no running channel consumes
      # @param bus [Bus::MessageBus] gateway message bus
      # @return [void]
      def drop_unrouted_outbound(bus)
        loop { bus.drop_outbound(bus.consume_outbound) }
      end

      default_task :call
    end
  end
end
