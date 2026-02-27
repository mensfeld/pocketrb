# frozen_string_literal: true

require "telegram/bot"

module Pocketrb
  module Channels
    # Telegram channel using long polling
    # Simple and reliable - no webhook/public IP needed
    class Telegram < Base
      # Markdown to HTML conversion patterns for Telegram formatting
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

      # Telegram file download URL template
      TELEGRAM_FILE_URL = "https://api.telegram.org/file/bot%<token>s/%<path>s"

      # Special commands that bypass the agent
      SPECIAL_COMMANDS = %w[/status /jobs /cron /help].freeze

      attr_accessor :status_context

      # Initialize Telegram channel
      # @param bus [Bus::MessageBus] Message bus for publishing and consuming messages
      # @param token [String] Telegram bot API token
      # @param allowed_users [Array<String, Integer>, nil] Allowed usernames or user IDs (nil = allow all)
      # @param download_media [Boolean] Whether to download and process media attachments (defaults to true)
      def initialize(bus:, token:, allowed_users: nil, download_media: true)
        super(bus: bus, name: :telegram)
        @token = token
        @allowed_users = allowed_users # Array of usernames or user IDs, nil = allow all
        @download_media = download_media
        @bot = nil
        @chat_ids = {} # Map sender_id to chat_id for replies
        @media_processor = Media::Processor.new
        @status_context = {} # Will hold job_manager, cron_service, etc.
        @started_at = Time.now
      end

      protected

      def run_inbound_loop
        Pocketrb.logger.info("Starting Telegram bot (polling mode)...")

        # Run the blocking telegram listener in a separate thread
        # so Async outbound consumer can process messages
        @listener_thread = Thread.new do
          ::Telegram::Bot::Client.run(@token) do |bot|
            @bot = bot

            # Get bot info
            me = bot.api.get_me
            username = me.respond_to?(:username) ? me.username : me.dig("result", "username")
            Pocketrb.logger.info("Telegram bot @#{username} connected")

            bot.listen do |message|
              break unless @running

              handle_telegram_message(message)
            end
          end
        rescue StandardError => e
          Pocketrb.logger.error("Telegram listener error: #{e.message}")
        end

        # Keep the main fiber alive for async tasks
        sleep 0.1 while @running

        @listener_thread&.join
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
        unless message.text || message.caption || message.photo || message.voice || message.document || message.audio || message.video
          return
        end

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

        # Handle special commands (bypass agent)
        return if message.text && handle_special_command(message.text, chat_id)

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
        parts << "[Image attached - I can see this image]" if message.photo&.any? && @download_media

        parts << "[Voice message attached]" if message.voice

        parts << "[Audio: #{message.audio.title || message.audio.file_name || "audio"}]" if message.audio

        parts << "[Video attached]" if message.video

        parts << "[Document: #{message.document.file_name}]" if message.document

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

      def download_telegram_file(file_id, _type, mime_type, filename = nil)
        # Get file path from Telegram
        result = @bot.api.get_file(file_id: file_id)

        # Handle both telegram-bot-ruby v1 (hash) and v2 (typed object)
        file_path = if result.respond_to?(:file_path)
                      result.file_path
                    else
                      result.dig("result", "file_path")
                    end
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

      # Handle special commands that bypass the agent
      def handle_special_command(text, chat_id)
        cmd = text.strip.split.first&.downcase
        return false unless SPECIAL_COMMANDS.include?(cmd)

        response = case cmd
                   when "/status" then build_status_response
                   when "/jobs" then build_jobs_response
                   when "/cron" then build_cron_response
                   when "/help" then build_help_response
                   else return false
                   end

        @bot.api.send_message(
          chat_id: chat_id,
          text: response,
          parse_mode: "HTML"
        )
        true
      rescue StandardError => e
        Pocketrb.logger.error("Special command error: #{e.message}")
        @bot.api.send_message(chat_id: chat_id, text: "Error: #{e.message}")
        true
      end

      def build_status_response
        lines = []
        lines << "━━━━━━━━━━━━━━━━━━━━━━━━━━"
        lines << "🤖 <b>Pocketrb Status</b>"
        lines << "━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # Uptime
        uptime = format_uptime(Time.now - @started_at)
        lines << "⏱ Uptime: #{uptime}"

        # Provider info
        if @status_context[:provider]
          provider = @status_context[:provider]
          lines << "🔌 Provider: #{provider.class.name.split("::").last}"
          lines << "🧠 Model: #{@status_context[:model] || "default"}"
        end

        # Claude CLI status (if using claude_cli provider)
        claude_status = get_claude_cli_status
        if claude_status
          lines << ""
          lines << "🖥 <b>Claude CLI:</b>"
          claude_status.each { |line| lines << "  #{line}" }
        end

        # Background jobs
        jobs_info = get_jobs_summary
        lines << ""
        lines << "📋 <b>Background Jobs:</b> #{jobs_info[:summary]}"
        jobs_info[:jobs].first(3).each { |j| lines << "  • #{j}" }
        lines << "  ... and #{jobs_info[:jobs].length - 3} more" if jobs_info[:jobs].length > 3

        # Cron jobs
        cron_info = get_cron_summary
        lines << ""
        lines << "⏰ <b>Scheduled Jobs:</b> #{cron_info[:summary]}"
        cron_info[:jobs].first(3).each { |j| lines << "  • #{j}" }
        lines << "  ... and #{cron_info[:jobs].length - 3} more" if cron_info[:jobs].length > 3

        # Session info
        if @status_context[:sessions]
          session_count = begin
            @status_context[:sessions].list_sessions.length
          rescue StandardError
            0
          end
          lines << ""
          lines << "💬 Sessions: #{session_count}"
        end

        lines << "━━━━━━━━━━━━━━━━━━━━━━━━━━"
        lines.join("\n")
      end

      def build_jobs_response
        jobs_info = get_jobs_summary
        return "No background jobs." if jobs_info[:jobs].empty?

        lines = ["<b>📋 Background Jobs</b>", ""]

        running, completed = jobs_info[:all].partition { |j| j[:running] }

        if running.any?
          lines << "<b>Running:</b>"
          running.each do |job|
            lines << "  🟢 [#{job[:job_id]}] #{job[:name]}"
          end
          lines << ""
        end

        if completed.any?
          lines << "<b>Completed:</b>"
          completed.first(10).each do |job|
            lines << "  ⚪ [#{job[:job_id]}] #{job[:name]}"
          end
        end

        lines.join("\n")
      end

      def build_cron_response
        cron_info = get_cron_summary
        return "No scheduled jobs." if cron_info[:all].empty?

        lines = ["<b>⏰ Scheduled Jobs</b>", ""]

        cron_info[:all].each do |job|
          status = job.enabled ? "🟢" : "⚪"
          next_run = if job.state.next_run_at_ms
                       Time.at(job.state.next_run_at_ms / 1000).strftime("%m/%d %H:%M")
                     else
                       "—"
                     end
          lines << "#{status} <b>#{job.name}</b> [#{job.id}]"
          lines << "    Next: #{next_run}"
          lines << "    #{job.payload.message[0..40]}#{"..." if job.payload.message.length > 40}"
          lines << ""
        end

        lines.join("\n")
      end

      def build_help_response
        <<~HELP
          <b>🤖 Pocketrb Commands</b>

          <b>/status</b> - Show system status
          <b>/jobs</b> - List background jobs
          <b>/cron</b> - List scheduled tasks
          <b>/help</b> - Show this help

          Or just chat naturally - I can:
          • Execute commands
          • Read/write files
          • Search the web
          • Schedule reminders
          • Remember things
        HELP
      end

      def get_claude_cli_status
        # Check if claude processes are running
        claude_pids = `pgrep -f "claude" 2>/dev/null`.strip.split("\n")
        return nil if claude_pids.empty?

        lines = []

        claude_pids.each do |pid|
          # Get process info
          cmd = `ps -p #{pid} -o args= 2>/dev/null`.strip
          next if cmd.empty? || cmd.include?("pgrep")

          # Get runtime
          etime = `ps -p #{pid} -o etime= 2>/dev/null`.strip

          # Try to get what it's doing (check /proc on Linux)
          status = "running"
          if File.exist?("/proc/#{pid}/fd")
            # Check if it's doing I/O
            fd_count = begin
              Dir.glob("/proc/#{pid}/fd/*").length
            rescue StandardError
              0
            end
            status = "active (#{fd_count} fds)" if fd_count > 10
          end

          # Truncate command for display
          display_cmd = cmd.length > 50 ? "#{cmd[0..47]}..." : cmd
          lines << "PID #{pid}: #{status}"
          lines << "  #{display_cmd}" if lines.length < 6
          lines << "  Time: #{etime}" if etime.length.positive?
        end

        lines.empty? ? nil : lines.first(8)
      end

      def get_jobs_summary
        job_manager = @status_context[:job_manager]

        # Create job manager lazily from memory_dir if not provided
        if job_manager.nil? && @status_context[:memory_dir]
          begin
            job_manager = Tools::BackgroundJobManager.new(workspace: @status_context[:memory_dir])
          rescue StandardError
            # Ignore if we can't create it
          end
        end

        return { summary: "N/A", jobs: [], all: [] } unless job_manager&.available?

        jobs = job_manager.list
        running = jobs.count { |j| j[:running] }
        completed = jobs.length - running

        {
          summary: "#{running} running, #{completed} completed",
          jobs: jobs.map { |j| "#{j[:running] ? "🟢" : "⚪"} #{j[:name][0..30]}" },
          all: jobs
        }
      end

      def get_cron_summary
        cron_service = @status_context[:cron_service]
        return { summary: "N/A", jobs: [], all: [] } unless cron_service

        jobs = cron_service.list_jobs(include_disabled: true)
        enabled = jobs.count(&:enabled)

        {
          summary: "#{enabled} active, #{jobs.length - enabled} disabled",
          jobs: jobs.select(&:enabled).map { |j| j.name.to_s },
          all: jobs
        }
      end

      def format_uptime(seconds)
        seconds = seconds.to_i
        if seconds < 60
          "#{seconds}s"
        elsif seconds < 3600
          "#{seconds / 60}m #{seconds % 60}s"
        elsif seconds < 86_400
          "#{seconds / 3600}h #{(seconds % 3600) / 60}m"
        else
          "#{seconds / 86_400}d #{(seconds % 86_400) / 3600}h"
        end
      end

      def markdown_to_telegram_html(text)
        return "" if text.nil? || text.empty?

        result = text.dup

        # Extract and protect code blocks
        code_blocks = []
        result.gsub!(/```\w*\n?([\s\S]*?)```/) do
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
