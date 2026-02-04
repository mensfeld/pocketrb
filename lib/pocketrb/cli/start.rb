# frozen_string_literal: true

module Pocketrb
  class CLI
    # Start command - continuous mode with CLI channel
    class Start < Base
      desc "start", "Start the agent in continuous mode"
      option :model, type: :string, aliases: "-m", desc: "Model to use"
      option :provider, type: :string, aliases: "-p", desc: "LLM provider (anthropic, openrouter)"
      option :channel, type: :string, aliases: "-c", default: "cli", desc: "Channel to connect to"

      # Starts the agent in continuous mode with CLI channel
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
          max_iterations: config[:max_iterations],
          mcp_endpoint: config[:mcp_endpoint]
        )

        say "Pocketrb started with #{config[:provider]}/#{config[:model]}", :green
        say "Workspace: #{workspace}"
        say "Memory: #{memory_dir}" if memory_dir != workspace
        say "Press Ctrl+C to stop\n"

        # Start CLI channel
        channel = Pocketrb::Channels::CLI.new(bus: bus)

        Async do
          agent_loop.run
          channel.run
        end
      rescue Interrupt
        say "\nShutting down...", :yellow
      end

      default_task :call
    end
  end
end
