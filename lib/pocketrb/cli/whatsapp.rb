# frozen_string_literal: true

module Pocketrb
  class CLI
    # WhatsApp command - runs agent as a WhatsApp bot
    class WhatsApp < Base
      desc "whatsapp", "Run as a WhatsApp bot (requires Node.js bridge)"
      option :model, type: :string, aliases: "-m", desc: "Model to use"
      option :provider, type: :string, aliases: "-p", desc: "LLM provider"
      option :bridge_url, type: :string, default: "ws://localhost:3001", desc: "WhatsApp bridge WebSocket URL"
      option :allowed_users, type: :array, aliases: "-u", desc: "Allowed phone numbers"

      # Runs the agent as a WhatsApp bot using a WebSocket bridge
      # @return [void]
      def call
        setup_logging
        workspace = resolve_workspace
        memory_dir = resolve_memory_dir

        config = Pocketrb::Config.load(memory_dir)
        config[:model] = options[:model] if options[:model]
        config[:provider] = options[:provider] if options[:provider]

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

        say "Starting Pocketrb WhatsApp Bot", :green
        say "Provider: #{config[:provider]}/#{config[:model]}"
        say "Bridge: #{options[:bridge_url]}"
        say "Workspace: #{workspace}"
        say "Memory: #{memory_dir}" if memory_dir != workspace
        say "Press Ctrl+C to stop\n"

        channel = Pocketrb::Channels::WhatsApp.new(
          bus: bus,
          bridge_url: options[:bridge_url],
          allowed_users: options[:allowed_users]
        )

        Async do
          agent_loop.run
          channel.run
        end
      rescue Interrupt
        say "\nShutting down WhatsApp bot...", :yellow
      end

      default_task :call
    end
  end
end
