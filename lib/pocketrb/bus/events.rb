# frozen_string_literal: true

module Pocketrb
  # Bus module provides the message bus architecture for multi-channel communication
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
      # Initialize an inbound message
      # @param channel [Symbol] Channel identifier (e.g., :cli, :telegram, :discord)
      # @param sender_id [String] User or system identifier that sent this message
      # @param chat_id [String] Conversation or thread identifier for session tracking
      # @param content [String] Text content of the message
      # @param media [Array<Media>] Array of media attachments (defaults to empty)
      # @param metadata [Hash] Channel-specific metadata (defaults to empty hash)
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
      # Initialize an outbound message
      # @param channel [Symbol] Target channel identifier
      # @param chat_id [String] Target chat or conversation identifier
      # @param content [String] Text content to send
      # @param media [Array<Media>] Array of media to attach (defaults to empty)
      # @param reply_to [String, nil] Message ID to reply to (optional)
      # @param metadata [Hash] Channel-specific options (defaults to empty hash)
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
      # Initialize a media attachment
      # @param type [Symbol] Media type (:image, :file, :audio, or :video)
      # @param path [String] File system path or URL to the media
      # @param mime_type [String] MIME type of the media (e.g., "image/png")
      # @param filename [String, nil] Original filename (optional)
      # @param data [String, nil] Base64 encoded data for inline media (optional)
      def initialize(type:, path:, mime_type:, filename: nil, data: nil)
        super
      end

      # Check if media is an image type
      # @return [Boolean] true if type is :image
      def image?
        type == :image
      end

      # Check if media is a file type
      # @return [Boolean] true if type is :file
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
      # Initialize a tool execution event
      # @param tool_call_id [String] LLM-generated identifier linking this execution to the request
      # @param name [String] Name of the tool being executed
      # @param arguments [Hash] Arguments passed to the tool
      # @param result [String, nil] Execution result if successful (optional)
      # @param error [String, nil] Error message if execution failed (optional)
      # @param duration_ms [Integer, nil] Execution duration in milliseconds (optional)
      def initialize(tool_call_id:, name:, arguments:, result: nil, error: nil, duration_ms: nil)
        super
      end

      # Check if tool execution succeeded
      # @return [Boolean] true if no error occurred
      def success?
        error.nil?
      end

      # Check if tool execution failed
      # @return [Boolean] true if an error occurred
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
      # Initialize a state change event
      # @param session_key [String] Session identifier for the agent
      # @param from_state [Symbol] Previous state the agent was in
      # @param to_state [Symbol] New state the agent is transitioning to
      # @param reason [String, nil] Optional reason for the state change
      def initialize(session_key:, from_state:, to_state:, reason: nil)
        super
      end
    end
  end
end
