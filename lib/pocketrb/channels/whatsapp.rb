# frozen_string_literal: true

require "json"
require "socket"

module Pocketrb
  module Channels
    # WhatsApp channel via Node.js bridge WebSocket
    # Connects to a whatsapp-web.js bridge running on localhost
    #
    # Bridge Protocol:
    # - Receive: {type: "message", sender: "...", content: "...", timestamp: ..., isGroup: bool}
    # - Send: {type: "send", to: "phone@s.whatsapp.net", text: "..."}
    # - Status: {type: "status", status: "connected"}
    # - QR: {type: "qr", qr: "data:image/png;base64,..."}
    class WhatsApp < Base
      RECONNECT_DELAY = 5
      DEFAULT_BRIDGE_URL = "ws://localhost:3001"

      def initialize(bus:, bridge_url: DEFAULT_BRIDGE_URL, allowed_users: nil, download_media: true)
        super(bus: bus, name: :whatsapp)
        @bridge_url = bridge_url
        @allowed_users = allowed_users # Array of phone numbers
        @download_media = download_media
        @ws = nil
        @connected = false
        @media_processor = Media::Processor.new
      end

      # Check if we can connect to the bridge
      def available?
        require "websocket-client-simple"
        true
      rescue LoadError
        false
      end

      protected

      def run_inbound_loop
        require "websocket-client-simple"

        Pocketrb.logger.info("Starting WhatsApp channel (bridge: #{@bridge_url})")

        loop do
          break unless @running

          begin
            connect_and_listen
          rescue StandardError => e
            Pocketrb.logger.error("WhatsApp connection error: #{e.message}")
          end

          if @running
            Pocketrb.logger.info("Reconnecting to WhatsApp bridge in #{RECONNECT_DELAY}s...")
            sleep RECONNECT_DELAY
          end
        end
      rescue LoadError
        Pocketrb.logger.error("websocket-client-simple gem not installed. Run: gem install websocket-client-simple")
        raise
      end

      def send_message(message)
        return unless @ws && @connected

        jid = to_jid(message.chat_id)
        payload = {
          type: "send",
          to: jid,
          text: message.content
        }

        @ws.send(payload.to_json)
        Pocketrb.logger.debug("WhatsApp: sent message to #{jid}")
      rescue StandardError => e
        Pocketrb.logger.error("WhatsApp send error: #{e.message}")
      end

      private

      def connect_and_listen
        channel = self

        @ws = WebSocket::Client::Simple.connect(@bridge_url)

        @ws.on :open do
          channel.instance_variable_set(:@connected, true)
          Pocketrb.logger.info("WhatsApp: connected to bridge")
        end

        @ws.on :message do |msg|
          channel.send(:handle_bridge_message, msg.data)
        end

        @ws.on :error do |e|
          Pocketrb.logger.error("WhatsApp WebSocket error: #{e.message}")
        end

        @ws.on :close do |_e|
          channel.instance_variable_set(:@connected, false)
          Pocketrb.logger.warn("WhatsApp: disconnected from bridge")
        end

        # Block until disconnected
        sleep 0.5 while @ws.open? && @running
      end

      def handle_bridge_message(data)
        message = JSON.parse(data)

        case message["type"]
        when "message"
          handle_incoming_message(message)
        when "status"
          Pocketrb.logger.info("WhatsApp status: #{message["status"]}")
        when "qr"
          handle_qr(message)
        when "ready"
          Pocketrb.logger.info("WhatsApp: ready")
        when "authenticated"
          Pocketrb.logger.info("WhatsApp: authenticated")
        when "error"
          Pocketrb.logger.error("WhatsApp error: #{message["error"]}")
        else
          Pocketrb.logger.debug("WhatsApp: unknown message type: #{message["type"]}")
        end
      rescue JSON::ParserError => e
        Pocketrb.logger.warn("WhatsApp: invalid JSON: #{e.message}")
      end

      def handle_incoming_message(message)
        sender = extract_phone(message["sender"] || message["from"])
        return unless allowed_user?(sender)

        # Skip if it's from self
        return if message["fromMe"]

        content = message["content"] || message["body"] || ""
        chat_id = message["sender"] || message["from"]
        is_group = message["isGroup"] || chat_id.include?("@g.us")

        # Process media if present
        media = []
        if @download_media && message["hasMedia"]
          media_item = process_whatsapp_media(message)
          media << media_item if media_item

          # Add indicator to content
          content = "[Image attached - I can see this image]\n#{content}".strip if media_item&.image?
          content = "[Media attached: #{media_item&.filename}]\n#{content}".strip if media_item && !media_item.image?
        end

        # Skip if no content and no media
        return if content.empty? && media.empty?

        Pocketrb.logger.debug("WhatsApp message from #{sender}: #{content[0..50]}... (#{media.size} media)")

        inbound = create_inbound_message(
          sender_id: sender,
          chat_id: chat_id,
          content: content.empty? ? "[media only]" : content,
          media: media,
          metadata: {
            is_group: is_group,
            timestamp: message["timestamp"],
            message_id: message["id"]
          }
        )

        @bus.publish_inbound(inbound)
      end

      def process_whatsapp_media(message)
        return nil unless message["mediaData"] || message["mediaUrl"]

        mime_type = message["mimetype"] || message["mediaType"] || "application/octet-stream"
        filename = message["filename"] || "media_#{Time.now.to_i}.#{extension_for_mime(mime_type)}"

        if message["mediaData"]
          # Base64 encoded data from bridge
          require "base64"
          bytes = Base64.decode64(message["mediaData"])
          @media_processor.from_bytes(bytes, mime_type: mime_type, filename: filename)
        elsif message["mediaUrl"]
          # URL to download
          @media_processor.download(message["mediaUrl"], filename: filename, mime_type: mime_type)
        end
      rescue StandardError => e
        Pocketrb.logger.warn("Failed to process WhatsApp media: #{e.message}")
        nil
      end

      def extension_for_mime(mime_type)
        case mime_type
        when %r{^image/jpeg} then "jpg"
        when %r{^image/png} then "png"
        when %r{^image/gif} then "gif"
        when %r{^image/webp} then "webp"
        when %r{^audio/ogg} then "ogg"
        when %r{^audio/mpeg} then "mp3"
        when %r{^video/mp4} then "mp4"
        else "bin"
        end
      end

      def handle_qr(message)
        return unless message["qr"]

        Pocketrb.logger.info("WhatsApp: QR code received. Scan in bridge terminal or use the data URL.")
        # Could save to file or display in terminal if needed
      end

      def allowed_user?(phone)
        return true if @allowed_users.nil? || @allowed_users.empty?

        normalized = normalize_phone(phone)
        @allowed_users.any? { |allowed| normalize_phone(allowed) == normalized }
      end

      def to_jid(phone)
        return phone if phone.include?("@")

        # Remove any non-digits
        clean = phone.gsub(/\D/, "")
        "#{clean}@s.whatsapp.net"
      end

      def extract_phone(jid)
        return jid unless jid

        jid.split("@").first
      end

      def normalize_phone(phone)
        return nil unless phone

        phone.to_s.gsub(/\D/, "")
      end
    end
  end
end
