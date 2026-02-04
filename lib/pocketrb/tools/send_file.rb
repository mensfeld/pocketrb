# frozen_string_literal: true

module Pocketrb
  module Tools
    # Tool for sending files/images to chat channels
    class SendFile < Base
      ALLOWED_EXTENSIONS = %w[
        .jpg .jpeg .png .gif .webp .bmp
        .pdf .txt .md .json .csv .xml
        .mp3 .ogg .wav .m4a
        .mp4 .webm .mov
        .zip .tar .gz
      ].freeze

      def name
        "send_file"
      end

      def description
        "Send a file (image, document, audio, video) to the user via chat. Use this to share generated content, screenshots, reports, or any files."
      end

      def parameters
        {
          type: "object",
          properties: {
            path: {
              type: "string",
              description: "Path to the file to send"
            },
            caption: {
              type: "string",
              description: "Optional caption/message to send with the file"
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
          required: ["path"]
        }
      end

      def execute(path:, caption: nil, channel: nil, chat_id: nil)
        # Resolve path
        file_path = resolve_path(path)
        return error("File not found: #{path}") unless File.exist?(file_path)
        return error("Not a file: #{path}") unless File.file?(file_path)

        # Check file size (Telegram limit is 50MB for bots)
        size = File.size(file_path)
        return error("File too large (#{size / 1_000_000}MB). Max 50MB.") if size > 50_000_000

        # Check extension
        ext = File.extname(file_path).downcase
        return error("File type not allowed: #{ext}") unless ALLOWED_EXTENSIONS.include?(ext)

        # Use defaults from context
        channel = (channel || @context[:default_channel])&.to_sym
        chat_id ||= @context[:default_chat_id]

        return error("No channel specified and no default channel") unless channel
        return error("No chat_id specified and no default chat_id") unless chat_id
        return error("Message bus not available") unless bus

        # Create media object
        media = create_media(file_path)

        # Send message with media
        outbound = Bus::OutboundMessage.new(
          channel: channel,
          chat_id: chat_id,
          content: caption || "",
          media: [media]
        )

        bus.publish_outbound(outbound)
        Pocketrb.logger.info("File sent to #{channel}:#{chat_id}: #{file_path}")

        success("Sent #{File.basename(file_path)} to #{channel}")
      end

      def available?
        !bus.nil?
      end

      private

      def bus
        @context[:bus]
      end

      def resolve_path(path)
        return path if Pathname.new(path).absolute?

        workspace.join(path).to_s
      end

      def create_media(path)
        ext = File.extname(path).downcase
        mime_type = detect_mime_type(ext)
        type = detect_type(ext)

        Bus::Media.new(
          type: type,
          path: path,
          mime_type: mime_type,
          filename: File.basename(path),
          data: nil # Will be read from path when sending
        )
      end

      def detect_type(ext)
        case ext
        when ".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp"
          :image
        when ".mp3", ".ogg", ".wav", ".m4a"
          :audio
        when ".mp4", ".webm", ".mov"
          :video
        else
          :file
        end
      end

      def detect_mime_type(ext)
        {
          ".jpg" => "image/jpeg",
          ".jpeg" => "image/jpeg",
          ".png" => "image/png",
          ".gif" => "image/gif",
          ".webp" => "image/webp",
          ".bmp" => "image/bmp",
          ".pdf" => "application/pdf",
          ".txt" => "text/plain",
          ".md" => "text/markdown",
          ".json" => "application/json",
          ".csv" => "text/csv",
          ".xml" => "application/xml",
          ".mp3" => "audio/mpeg",
          ".ogg" => "audio/ogg",
          ".wav" => "audio/wav",
          ".m4a" => "audio/mp4",
          ".mp4" => "video/mp4",
          ".webm" => "video/webm",
          ".mov" => "video/quicktime",
          ".zip" => "application/zip",
          ".tar" => "application/x-tar",
          ".gz" => "application/gzip"
        }[ext] || "application/octet-stream"
      end
    end
  end
end
