# frozen_string_literal: true

module Pocketrb
  # Channels module provides multi-channel support (CLI, Telegram, WhatsApp, etc.)
  module Channels
    # Interactive CLI channel
    class CLI < Base
      # Initialize CLI channel
      # @param bus [Bus::MessageBus] Message bus for publishing and consuming messages
      # @param prompt [String] Command prompt string (defaults to "> ")
      def initialize(bus:, prompt: "> ")
        super(bus: bus, name: :cli)
        @prompt = prompt
        @output_mutex = Mutex.new
      end

      protected

      # Read user input from stdin and publish inbound messages
      def run_inbound_loop
        Async do
          while @running
            print @prompt
            input = read_input
            break if input.nil?

            next if input.empty?

            # Handle special commands
            next if handle_command(input)

            # Create and publish inbound message
            message = create_inbound_message(
              sender_id: "user",
              chat_id: "cli",
              content: input
            )

            @bus.publish_inbound(message)
          end
        end
      end

      # Print the outbound message content to stdout
      # @param message [Bus::OutboundMessage] outbound message to display
      def send_message(message)
        @output_mutex.synchronize do
          puts "\n#{format_output(message.content)}\n"
        end
      end

      private

      # Read a single line from stdin, returning nil on EOF or interrupt
      # @return [String, nil]
      def read_input
        line = $stdin.gets
        return nil if line.nil?

        line.chomp
      rescue Interrupt
        nil
      end

      # Process built-in CLI commands (exit, help, clear, stats)
      # @param input [String] raw user input to check for commands
      # @return [Boolean] true if input was a recognized command
      def handle_command(input)
        case input.downcase
        when "exit", "quit", "/exit", "/quit"
          @running = false
          puts "Goodbye!"
          true
        when "/help"
          print_help
          true
        when "/clear"
          system("clear") || system("cls")
          true
        when "/stats"
          print_stats
          true
        else
          false
        end
      end

      # Display available CLI commands
      def print_help
        puts <<~HELP

          Commands:
            /help   - Show this help
            /clear  - Clear the screen
            /stats  - Show message statistics
            /exit   - Exit the chat

        HELP
      end

      # Display message bus statistics
      def print_stats
        stats = @bus.stats.to_h
        puts <<~STATS

          Statistics:
            Inbound messages:  #{stats[:inbound]}
            Outbound messages: #{stats[:outbound]}
            Tool executions:   #{stats[:tool_executions]}

        STATS
      end

      # Format message content for terminal display
      # @param content [String, nil] raw message content
      # @return [String] formatted output string
      def format_output(content)
        return "" if content.nil? || content.empty?

        # Simple formatting - could be enhanced with tty-markdown
        content
      end
    end
  end
end
