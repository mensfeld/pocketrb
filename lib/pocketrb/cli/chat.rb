# frozen_string_literal: true

require "tty-spinner"

module Pocketrb
  class CLI
    # Chat command - interactive chat mode
    class Chat < Base
      desc "chat", "Interactive chat mode (single session)"
      option :model, type: :string, aliases: "-m", desc: "Model to use"
      option :provider, type: :string, aliases: "-p", desc: "LLM provider"
      option :system_prompt, type: :string, aliases: "-s", desc: "Custom system prompt"

      # Starts an interactive chat session with the agent
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
          system_prompt: options[:system_prompt],
          mcp_endpoint: config[:mcp_endpoint]
        )

        say "Pocketrb Chat - #{config[:model]}", :green
        say "Memory: #{memory_dir}" if memory_dir != workspace
        say "Type 'exit' or 'quit' to end session\n"

        Async do
          # Simple REPL
          loop do
            print "\n> "
            input = $stdin.gets&.chomp
            break if input.nil? || %w[exit quit].include?(input.downcase)

            next if input.empty?

            msg = Pocketrb::Bus::InboundMessage.new(
              channel: :cli,
              sender_id: "user",
              chat_id: "chat",
              content: input
            )

            spinner = TTY::Spinner.new("[:spinner] Thinking...", format: :dots)
            spinner.auto_spin

            response = agent_loop.process_message(msg)

            spinner.stop
            puts "\n#{response.content}" if response
          end
        end

        say "\nGoodbye!", :yellow
      end

      default_task :call
    end
  end
end
