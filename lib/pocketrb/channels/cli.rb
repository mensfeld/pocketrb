# frozen_string_literal: true

module Pocketrb
  # Channels module provides multi-channel support (CLI, Telegram, WhatsApp, etc.)
  module Channels
    # Interactive CLI channel
    class CLI < Base
      def initialize(bus:, prompt: "> ")
        super(bus: bus, name: :cli)
        @prompt = prompt
        @output_mutex = Mutex.new
      end

      protected

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

      def send_message(message)
        @output_mutex.synchronize do
          puts "\n#{format_output(message.content)}\n"
        end
      end

      private

      def read_input
        line = $stdin.gets
        return nil if line.nil?

        line.chomp
      rescue Interrupt
        nil
      end

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

      def print_help
        puts <<~HELP

          Commands:
            /help   - Show this help
            /clear  - Clear the screen
            /stats  - Show message statistics
            /exit   - Exit the chat

        HELP
      end

      def print_stats
        stats = @bus.stats.to_h
        puts <<~STATS

          Statistics:
            Inbound messages:  #{stats[:inbound]}
            Outbound messages: #{stats[:outbound]}
            Tool executions:   #{stats[:tool_executions]}

        STATS
      end

      def format_output(content)
        return "" if content.nil? || content.empty?

        # Simple formatting - could be enhanced with tty-markdown
        content
      end
    end
  end
end
