# frozen_string_literal: true

module Pocketrb
  module Bus
    # Inbound message from a channel to the agent
    InboundMessage = Data.define(
      :channel,      # Symbol - channel identifier (:cli, :telegram, :discord, etc.)
      :sender_id,    # String - unique sender identifier
      :chat_id,      # String - unique chat/conversation identifier
      :content,      # String - text content of the message
      :media,        # Array<Media> - attached media (images, files, etc.)
      :metadata      # Hash - channel-specific metadata
    ) do
      def initialize(channel:, sender_id:, chat_id:, content:, media: [], metadata: {})
        super
      end

      # Unique key for session management
      def session_key
        "#{channel}:#{chat_id}"
      end

      # Check if message has media attachments
      def has_media?
        media && !media.empty?
      end
    end

    # Outbound message from the agent to a channel
    OutboundMessage = Data.define(
      :channel,      # Symbol - target channel
      :chat_id,      # String - target chat/conversation
      :content,      # String - text content to send
      :media,        # Array<Media> - media to attach
      :reply_to,     # String|nil - message ID to reply to
      :metadata      # Hash - channel-specific options
    ) do
      def initialize(channel:, chat_id:, content:, media: [], reply_to: nil, metadata: {})
        super
      end
    end

    # Media attachment
    Media = Data.define(
      :type,         # Symbol - :image, :file, :audio, :video
      :path,         # String - file path or URL
      :mime_type,    # String - MIME type
      :filename,     # String|nil - original filename
      :data          # String|nil - base64 encoded data (for inline media)
    ) do
      def initialize(type:, path:, mime_type:, filename: nil, data: nil)
        super
      end

      def image?
        type == :image
      end

      def file?
        type == :file
      end
    end

    # Tool execution event
    ToolExecution = Data.define(
      :tool_call_id, # String - unique tool call identifier
      :name,         # String - tool name
      :arguments,    # Hash - tool arguments
      :result,       # String|nil - execution result
      :error,        # String|nil - error message if failed
      :duration_ms   # Integer|nil - execution time in milliseconds
    ) do
      def initialize(tool_call_id:, name:, arguments:, result: nil, error: nil, duration_ms: nil)
        super
      end

      def success?
        error.nil?
      end

      def failed?
        !success?
      end
    end

    # Agent state change event
    StateChange = Data.define(
      :session_key,  # String - session identifier
      :from_state,   # Symbol - previous state
      :to_state,     # Symbol - new state
      :reason        # String|nil - reason for change
    ) do
      def initialize(session_key:, from_state:, to_state:, reason: nil)
        super
      end
    end
  end
end
