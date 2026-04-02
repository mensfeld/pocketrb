# frozen_string_literal: true

# Pocketrb: Ruby AI agent with multi-LLM support and advanced planning capabilities
module Pocketrb
  module Channels
    # Base class for channel adapters
    class Base
      attr_reader :bus, :name

      # Initialize channel adapter
      # @param bus [Bus::MessageBus] Message bus for publishing and consuming messages
      # @param name [Symbol, nil] Channel name (defaults to class name)
      def initialize(bus:, name: nil)
        @bus = bus
        @name = name || self.class.name.split("::").last.downcase.to_sym
        @running = false
      end

      # Start the channel
      def run
        @running = true
        start_outbound_consumer
        run_inbound_loop
      end

      # Stop the channel
      def stop
        @running = false
      end

      # Check if channel is running
      def running?
        @running
      end

      protected

      # Override in subclasses to implement inbound message handling
      def run_inbound_loop
        raise NotImplementedError
      end

      # Override in subclasses to send outbound messages
      # @param message [Bus::OutboundMessage] outbound message to deliver
      def send_message(message)
        raise NotImplementedError
      end

      private

      # Consume outbound messages from the bus and dispatch to send_message
      def start_outbound_consumer
        Async do
          while @running
            message = @bus.consume_outbound
            next unless message.channel == @name

            send_message(message)
          end
        end
      end

      # Build an inbound message struct for publishing to the bus
      # @param sender_id [String]
      # @param chat_id [String] conversation or chat identifier
      # @param content [String] text content of the message
      # @param media [Array<Media::Item>] attached media items
      # @param metadata [Hash] extra channel-specific metadata
      # @return [Bus::InboundMessage]
      def create_inbound_message(sender_id:, chat_id:, content:, media: [], metadata: {})
        Bus::InboundMessage.new(
          channel: @name,
          sender_id: sender_id,
          chat_id: chat_id,
          content: content,
          media: media,
          metadata: metadata
        )
      end
    end
  end
end
