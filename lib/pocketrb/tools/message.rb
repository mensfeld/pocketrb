# frozen_string_literal: true

module Pocketrb
  module Tools
    # Tool for sending messages to chat channels programmatically
    class Message < Base
      # Tool name
      # @return [String]
      def name
        "message"
      end

      # Tool description
      # @return [String]
      def description
        "Send a message to a chat channel. Use this to proactively communicate with users, send notifications, or respond on specific channels."
      end

      # Parameter schema
      # @return [Hash]
      def parameters
        {
          type: "object",
          properties: {
            content: {
              type: "string",
              description: "The message content to send"
            },
            channel: {
              type: "string",
              description: "Target channel (telegram, whatsapp, cli). Uses default if not specified."
            },
            chat_id: {
              type: "string",
              description: "Recipient chat ID. Uses default if not specified."
            }
          },
          required: ["content"]
        }
      end

      # Execute message sending
      # @param content [String] Message text to send
      # @param channel [String, nil] Target channel name
      # @param chat_id [String, nil] Target chat identifier
      # @return [String] Success or error message
      def execute(content:, channel: nil, chat_id: nil)
        # Use defaults from context if not provided
        channel = (channel || @context[:default_channel])&.to_sym
        chat_id ||= @context[:default_chat_id]

        return error("No channel specified and no default channel in context") unless channel

        return error("No chat_id specified and no default chat_id in context") unless chat_id

        return error("Message bus not available in context") unless bus

        outbound = Bus::OutboundMessage.new(
          channel: channel,
          chat_id: chat_id,
          content: content
        )

        bus.publish_outbound(outbound)
        Pocketrb.logger.info("Message sent to #{channel}:#{chat_id}")

        success("Message sent to #{channel}:#{chat_id}")
      end

      # Check if message bus is available
      # @return [Boolean] True if bus is configured
      def available?
        !bus.nil?
      end

      private

      def bus
        @context[:bus]
      end
    end
  end
end
