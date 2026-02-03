# frozen_string_literal: true

require "telegram/bot"

module Pocketrb
  module Channels
    # Telegram channel using long polling
    # Simple and reliable - no webhook/public IP needed
    class Telegram < Base
      MARKDOWN_TO_HTML = {
        # Bold **text** or __text__
        /\*\*(.+?)\*\*/ => '<b>\1</b>',
        /__(.+?)__/ => '<b>\1</b>',
        # Italic _text_ (avoid matching inside words)
        /(?<![a-zA-Z0-9])_([^_]+)_(?![a-zA-Z0-9])/ => '<i>\1</i>',
        # Strikethrough ~~text~~
        /~~(.+?)~~/ => '<s>\1</s>',
        # Inline code `text`
        /`([^`]+)`/ => '<code>\1</code>'
      }.freeze

      TELEGRAM_FILE_URL = "https://api.telegram.org/file/bot%<token>s/%<path>s"

      def initialize(bus:, token:, allowed_users: nil, download_media: true)
        super(bus: bus, name: :telegram)
        @token = token
        @allowed_users = allowed_users # Array of usernames or user IDs, nil = allow all
        @download_media = download_media
        @bot = nil
        @chat_ids = {} # Map sender_id to chat_id for replies
        @media_processor = Media::Processor.new
      end

      protected

      def run_inbound_loop
        Pocketrb.logger.info("Starting Telegram bot (polling mode)...")

        ::Telegram::Bot::Client.run(@token) do |bot|
          @bot = bot

          # Get bot info
          me = bot.api.get_me["result"]
          Pocketrb.logger.info("Telegram bot @#{me["username"]} connected")

          bot.listen do |message|
            break unless @running

            handle_telegram_message(message)
          end
        end
      rescue StandardError => e
        Pocketrb.logger.error("Telegram error: #{e.message}")
        raise
      end

      def send_message(message)
        return unless @bot

        chat_id = message.chat_id.to_i

        # Send media attachments first
        message.media&.each do |media|
          send_media(chat_id, media)
        end

        # Send text content if present
        return if message.content.nil? || message.content.empty?

        html_content = markdown_to_telegram_html(message.content)

        @bot.api.send_message(
          chat_id: chat_id,
          text: html_content,
          parse_mode: "HTML",
          reply_to_message_id: message.reply_to
        )
      rescue StandardError => e
        Pocketrb.logger.warn("HTML parse failed, falling back to plain text: #{e.message}")
        begin
          @bot.api.send_message(
            chat_id: chat_id,
            text: message.content,
            reply_to_message_id: message.reply_to
          )
        rescue StandardError => e2
          Pocketrb.logger.error("Error sending Telegram message: #{e2.message}")
        end
      end

      def send_media(chat_id, media)
        case media.type
        when :image
          send_photo(chat_id, media)
        when :audio
          send_audio(chat_id, media)
        when :video
          send_video(chat_id, media)
        else
          send_document(chat_id, media)
        end
      rescue StandardError => e
        Pocketrb.logger.error("Error sending media: #{e.message}")
      end

      def send_photo(chat_id, media)
        file = Faraday::Multipart::FilePart.new(media.path, media.mime_type, media.filename)
        @bot.api.send_photo(chat_id: chat_id, photo: file)
      end

      def send_audio(chat_id, media)
        file = Faraday::Multipart::FilePart.new(media.path, media.mime_type, media.filename)
        @bot.api.send_audio(chat_id: chat_id, audio: file)
      end

      def send_video(chat_id, media)
        file = Faraday::Multipart::FilePart.new(media.path, media.mime_type, media.filename)
        @bot.api.send_video(chat_id: chat_id, video: file)
      end

      def send_document(chat_id, media)
        file = Faraday::Multipart::FilePart.new(media.path, media.mime_type, media.filename)
        @bot.api.send_document(chat_id: chat_id, document: file)
      end

      private

      def handle_telegram_message(message)
        return unless message.is_a?(::Telegram::Bot::Types::Message)
        return unless message.text || message.caption || message.photo || message.voice || message.document || message.audio || message.video

        user = message.from
        return unless user

        # Check allowlist
        if @allowed_users && !allowed_user?(user)
          Pocketrb.logger.debug("Ignoring message from non-allowed user: #{user.username || user.id}")
          return
        end

        chat_id = message.chat.id
        sender_id = build_sender_id(user)

        # Store chat_id for replies
        @chat_ids[sender_id] = chat_id

        # Build content and download media
        content = build_content(message)
        media = download_media(message)

        Pocketrb.logger.debug("Telegram message from #{sender_id}: #{content[0..50]}... (#{media.size} media)")

        # Create and publish inbound message
        inbound = create_inbound_message(
          sender_id: sender_id,
          chat_id: chat_id.to_s,
          content: content,
          media: media,
          metadata: {
            message_id: message.message_id,
            user_id: user.id,
            username: user.username,
            first_name: user.first_name,
            is_group: message.chat.type != "private"
          }
        )

        @bus.publish_inbound(inbound)
      end

      def build_sender_id(user)
        if user.username
          "#{user.id}|#{user.username}"
        else
          user.id.to_s
        end
      end

      def build_content(message)
        parts = []
        parts << message.text if message.text
        parts << message.caption if message.caption

        # Add descriptive text for media (actual media is in media array)
        if message.photo&.any?
          parts << "[Image attached - I can see this image]" if @download_media
        end

        if message.voice
          parts << "[Voice message attached]"
        end

        if message.audio
          parts << "[Audio: #{message.audio.title || message.audio.file_name || 'audio'}]"
        end

        if message.video
          parts << "[Video attached]"
        end

        if message.document
          parts << "[Document: #{message.document.file_name}]"
        end

        parts.empty? ? "[empty message]" : parts.join("\n")
      end

      def download_media(message)
        return [] unless @download_media

        media = []

        # Download photos (get largest size)
        if message.photo&.any?
          photo = message.photo.max_by(&:file_size)
          media_item = download_telegram_file(photo.file_id, :image, "image/jpeg")
          media << media_item if media_item
        end

        # Download voice messages
        if message.voice
          media_item = download_telegram_file(
            message.voice.file_id,
            :audio,
            message.voice.mime_type || "audio/ogg"
          )
          media << media_item if media_item
        end

        # Download audio files
        if message.audio
          media_item = download_telegram_file(
            message.audio.file_id,
            :audio,
            message.audio.mime_type || "audio/mpeg",
            message.audio.file_name
          )
          media << media_item if media_item
        end

        # Download videos
        if message.video
          media_item = download_telegram_file(
            message.video.file_id,
            :video,
            message.video.mime_type || "video/mp4",
            message.video.file_name
          )
          media << media_item if media_item
        end

        # Download documents
        if message.document
          media_item = download_telegram_file(
            message.document.file_id,
            :file,
            message.document.mime_type || "application/octet-stream",
            message.document.file_name
          )
          media << media_item if media_item
        end

        media
      end

      def download_telegram_file(file_id, type, mime_type, filename = nil)
        # Get file path from Telegram
        result = @bot.api.get_file(file_id: file_id)
        file_path = result.dig("result", "file_path")
        return nil unless file_path

        # Build download URL
        url = format(TELEGRAM_FILE_URL, token: @token, path: file_path)

        # Download and process
        filename ||= File.basename(file_path)
        @media_processor.download(url, filename: filename, mime_type: mime_type)
      rescue StandardError => e
        Pocketrb.logger.warn("Failed to download Telegram file #{file_id}: #{e.message}")
        nil
      end

      def allowed_user?(user)
        return true if @allowed_users.nil? || @allowed_users.empty?

        @allowed_users.any? do |allowed|
          allowed.to_s == user.id.to_s ||
            allowed.to_s.downcase == user.username&.downcase
        end
      end

      def markdown_to_telegram_html(text)
        return "" if text.nil? || text.empty?

        result = text.dup

        # Extract and protect code blocks
        code_blocks = []
        result.gsub!(/```[\w]*\n?([\s\S]*?)```/) do
          code_blocks << Regexp.last_match(1)
          "\x00CB#{code_blocks.length - 1}\x00"
        end

        # Extract and protect inline code
        inline_codes = []
        result.gsub!(/`([^`]+)`/) do
          inline_codes << Regexp.last_match(1)
          "\x00IC#{inline_codes.length - 1}\x00"
        end

        # Remove headers (# ## ### etc)
        result.gsub!(/^\#{1,6}\s+(.+)$/, '\1')

        # Remove blockquotes
        result.gsub!(/^>\s*(.*)$/, '\1')

        # Escape HTML
        result = result.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")

        # Links [text](url)
        result.gsub!(/\[([^\]]+)\]\(([^)]+)\)/, '<a href="\2">\1</a>')

        # Bold
        result.gsub!(/\*\*(.+?)\*\*/, '<b>\1</b>')
        result.gsub!(/__(.+?)__/, '<b>\1</b>')

        # Italic (avoid matching inside words)
        result.gsub!(/(?<![a-zA-Z0-9])_([^_]+)_(?![a-zA-Z0-9])/, '<i>\1</i>')

        # Strikethrough
        result.gsub!(/~~(.+?)~~/, '<s>\1</s>')

        # Bullet lists
        result.gsub!(/^[-*]\s+/, "- ")

        # Restore inline code
        inline_codes.each_with_index do |code, i|
          escaped = code.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
          result.gsub!("\x00IC#{i}\x00", "<code>#{escaped}</code>")
        end

        # Restore code blocks
        code_blocks.each_with_index do |code, i|
          escaped = code.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
          result.gsub!("\x00CB#{i}\x00", "<pre><code>#{escaped}</code></pre>")
        end

        result
      end
    end
  end
end
