# frozen_string_literal: true

require "base64"
require "fileutils"
require "tmpdir"

module Pocketrb
  module Media
    # Handles media processing: downloading, encoding, type detection
    class Processor
      # Supported image MIME types for vision models
      VISION_IMAGE_TYPES = %w[
        image/jpeg
        image/png
        image/gif
        image/webp
      ].freeze

      # Audio types that can be transcribed
      AUDIO_TYPES = %w[
        audio/ogg
        audio/mpeg
        audio/mp3
        audio/wav
        audio/webm
        audio/m4a
      ].freeze

      # Max file size for inline encoding (5MB)
      MAX_INLINE_SIZE = 5 * 1024 * 1024

      attr_reader :cache_dir

      def initialize(cache_dir: nil)
        @cache_dir = cache_dir || default_cache_dir
        ensure_cache_dir!
      end

      # Download media from URL and return Media object
      # @param url [String] URL to download
      # @param filename [String, nil] Original filename
      # @param mime_type [String, nil] Known MIME type
      # @return [Bus::Media]
      def download(url, filename: nil, mime_type: nil)
        require "faraday"

        response = Faraday.get(url)
        raise MediaError, "Failed to download: HTTP #{response.status}" unless response.success?

        content_type = mime_type || response.headers["content-type"]&.split(";")&.first || "application/octet-stream"
        filename ||= extract_filename(url, content_type)

        # Save to cache
        cache_path = cache_file_path(filename)
        File.binwrite(cache_path, response.body)

        type = detect_type(content_type)
        data = encode_if_small(response.body, content_type)

        Bus::Media.new(
          type: type,
          path: cache_path,
          mime_type: content_type,
          filename: filename,
          data: data
        )
      end

      # Process a local file into a Media object
      # @param path [String] File path
      # @param mime_type [String, nil] Override MIME type
      # @return [Bus::Media]
      def from_file(path, mime_type: nil)
        raise MediaError, "File not found: #{path}" unless File.exist?(path)

        content = File.binread(path)
        content_type = mime_type || detect_mime_type(path)
        filename = File.basename(path)
        type = detect_type(content_type)
        data = encode_if_small(content, content_type)

        Bus::Media.new(
          type: type,
          path: path,
          mime_type: content_type,
          filename: filename,
          data: data
        )
      end

      # Encode raw bytes into a Media object
      # @param bytes [String] Raw binary data
      # @param mime_type [String] MIME type
      # @param filename [String, nil] Filename
      # @return [Bus::Media]
      def from_bytes(bytes, mime_type:, filename: nil)
        type = detect_type(mime_type)
        filename ||= "media_#{Time.now.to_i}.#{extension_for(mime_type)}"

        # Save to cache
        cache_path = cache_file_path(filename)
        File.binwrite(cache_path, bytes)

        data = encode_if_small(bytes, mime_type)

        Bus::Media.new(
          type: type,
          path: cache_path,
          mime_type: mime_type,
          filename: filename,
          data: data
        )
      end

      # Check if media is a vision-compatible image
      # @param media [Bus::Media]
      # @return [Boolean]
      def vision_compatible?(media)
        VISION_IMAGE_TYPES.include?(media.mime_type)
      end

      # Check if media is audio that can be transcribed
      # @param media [Bus::Media]
      # @return [Boolean]
      def audio?(media)
        AUDIO_TYPES.include?(media.mime_type) || media.type == :audio
      end

      # Get base64 data for media (loads from file if needed)
      # @param media [Bus::Media]
      # @return [String] Base64 encoded data
      def get_base64(media)
        return media.data if media.data

        content = File.binread(media.path)
        Base64.strict_encode64(content)
      end

      # Format media for Anthropic vision API
      # @param media [Bus::Media]
      # @return [Hash] Anthropic image content block
      def format_for_anthropic(media)
        unless vision_compatible?(media)
          return { type: "text", text: "[Attached file: #{media.filename} (#{media.mime_type})]" }
        end

        {
          type: "image",
          source: {
            type: "base64",
            media_type: media.mime_type,
            data: get_base64(media)
          }
        }
      end

      # Clean up old cached files
      # @param older_than [Integer] Age in seconds
      def cleanup_cache(older_than: 86_400)
        return unless @cache_dir.exist?

        cutoff = Time.now - older_than
        Dir.glob(@cache_dir.join("*")).each do |file|
          File.delete(file) if File.mtime(file) < cutoff
        rescue StandardError
          # Ignore cleanup errors
        end
      end

      private

      def default_cache_dir
        Pathname.new(Dir.tmpdir).join("pocketrb-media")
      end

      def ensure_cache_dir!
        FileUtils.mkdir_p(@cache_dir)
      end

      def cache_file_path(filename)
        # Sanitize filename and add timestamp to avoid conflicts
        safe_name = filename.gsub(/[^a-zA-Z0-9._-]/, "_")
        @cache_dir.join("#{Time.now.to_i}_#{safe_name}")
      end

      def detect_type(mime_type)
        case mime_type
        when %r{^image/}
          :image
        when %r{^audio/}
          :audio
        when %r{^video/}
          :video
        else
          :file
        end
      end

      def detect_mime_type(path)
        ext = File.extname(path).downcase
        MIME_TYPES[ext] || "application/octet-stream"
      end

      def encode_if_small(content, mime_type)
        return nil if content.bytesize > MAX_INLINE_SIZE
        return nil unless VISION_IMAGE_TYPES.include?(mime_type)

        Base64.strict_encode64(content)
      end

      def extract_filename(url, content_type)
        # Try to get filename from URL
        uri_path = begin
          URI.parse(url).path
        rescue StandardError
          ""
        end
        name = File.basename(uri_path)

        if name.empty? || !name.include?(".")
          ext = extension_for(content_type)
          name = "download_#{Time.now.to_i}.#{ext}"
        end

        name
      end

      def extension_for(mime_type)
        EXTENSIONS[mime_type] || "bin"
      end

      MIME_TYPES = {
        ".jpg" => "image/jpeg",
        ".jpeg" => "image/jpeg",
        ".png" => "image/png",
        ".gif" => "image/gif",
        ".webp" => "image/webp",
        ".mp3" => "audio/mpeg",
        ".ogg" => "audio/ogg",
        ".wav" => "audio/wav",
        ".m4a" => "audio/m4a",
        ".mp4" => "video/mp4",
        ".webm" => "video/webm",
        ".pdf" => "application/pdf",
        ".txt" => "text/plain",
        ".json" => "application/json"
      }.freeze

      EXTENSIONS = MIME_TYPES.invert.merge(
        "image/jpeg" => "jpg",
        "audio/mpeg" => "mp3",
        "audio/ogg" => "ogg"
      ).freeze
    end

    class MediaError < Pocketrb::Error; end
  end
end
