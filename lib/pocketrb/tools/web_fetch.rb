# frozen_string_literal: true

require "faraday"
require "faraday/follow_redirects"
require "uri"

module Pocketrb
  module Tools
    # Fetch and extract content from web pages
    class WebFetch < Base
      MAX_CONTENT_SIZE = 500_000 # characters
      TIMEOUT = 30 # seconds

      def name
        "web_fetch"
      end

      def description
        "Fetch content from a URL. Returns the text content of the page. Use for reading documentation, articles, or other web content."
      end

      def parameters
        {
          type: "object",
          properties: {
            url: {
              type: "string",
              description: "The URL to fetch"
            },
            selector: {
              type: "string",
              description: "CSS selector to extract specific content (optional)"
            }
          },
          required: ["url"]
        }
      end

      def execute(url:, selector: nil)
        # Validate URL
        uri = parse_url(url)
        return error("Invalid URL: #{url}") unless uri

        response = fetch_url(uri)
        return error("Failed to fetch URL: #{response[:error]}") if response[:error]

        content = extract_content(response[:body], selector)
        truncate_content(content)
      rescue Faraday::Error => e
        error("Request failed: #{e.message}")
      rescue StandardError => e
        error("Error fetching URL: #{e.message}")
      end

      private

      def parse_url(url)
        # Add https if no scheme
        url = "https://#{url}" unless url.match?(%r{^https?://})

        uri = URI.parse(url)
        return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

        uri
      rescue URI::InvalidURIError
        nil
      end

      def fetch_url(uri)
        conn = Faraday.new(url: uri.to_s) do |f|
          f.options.timeout = TIMEOUT
          f.options.open_timeout = 10
          f.headers["User-Agent"] = "Pocketrb/#{Pocketrb::VERSION} (Ruby AI Agent)"
          f.headers["Accept"] = "text/html,text/plain,application/json"
          f.response :follow_redirects, limit: 5
          f.adapter Faraday.default_adapter
        end

        response = conn.get

        if response.success?
          { body: response.body, content_type: response.headers["content-type"] }
        else
          { error: "HTTP #{response.status}" }
        end
      end

      def extract_content(body, selector)
        content_type = detect_content_type(body)

        case content_type
        when :html
          extract_html_content(body, selector)
        when :json
          format_json(body)
        else
          body
        end
      end

      def detect_content_type(body)
        return :json if body.strip.start_with?("{", "[")
        return :html if body.include?("<html") || body.include?("<body")

        :text
      end

      def extract_html_content(html, _selector)
        # Simple HTML to text conversion
        # A full implementation would use nokogiri
        text = html
               .gsub(%r{<script[^>]*>.*?</script>}mi, "")
               .gsub(%r{<style[^>]*>.*?</style>}mi, "")
               .gsub(%r{<head[^>]*>.*?</head>}mi, "")
               .gsub(%r{<nav[^>]*>.*?</nav>}mi, "")
               .gsub(%r{<footer[^>]*>.*?</footer>}mi, "")
               .gsub(/<[^>]+>/, "\n")
               .gsub("&nbsp;", " ")
               .gsub("&amp;", "&")
               .gsub("&lt;", "<")
               .gsub("&gt;", ">")
               .gsub("&quot;", '"')
               .gsub(/&#\d+;/) do |m|
                 [m[2..].to_i].pack("U")
        rescue StandardError
          m
        end
               .gsub(/\n{3,}/, "\n\n")
               .strip

        # Clean up whitespace
        text.lines.map(&:strip).reject(&:empty?).join("\n")
      end

      def format_json(body)
        data = JSON.parse(body)
        JSON.pretty_generate(data)
      rescue JSON::ParserError
        body
      end

      def truncate_content(content)
        return content if content.length <= MAX_CONTENT_SIZE

        truncated = content[0...MAX_CONTENT_SIZE]
        "#{truncated}\n\n... [Content truncated at #{MAX_CONTENT_SIZE} characters]"
      end
    end
  end
end
