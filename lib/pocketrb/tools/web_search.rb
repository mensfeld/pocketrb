# frozen_string_literal: true

require "faraday"
require "json"

module Pocketrb
  module Tools
    # Search the web using Brave Search API
    class WebSearch < Base
      # Brave Search API endpoint URL
      BRAVE_API_URL = "https://api.search.brave.com/res/v1/web/search"

      # Tool name
      # @return [String]
      def name
        "web_search"
      end

      # Tool description
      # @return [String]
      def description
        "Search the web for information. Returns relevant search results with titles, URLs, and descriptions."
      end

      # Parameter schema
      # @return [Hash]
      def parameters
        {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "The search query"
            },
            count: {
              type: "integer",
              description: "Number of results to return (default: 5, max: 20)"
            }
          },
          required: ["query"]
        }
      end

      # Check if tool is available
      # @return [Boolean] true if Brave API key is configured
      def available?
        api_key && !api_key.empty?
      end

      # Execute web search
      # @param query [String] Search query string
      # @param count [Integer] Number of results to return (1-20)
      # @return [String] Formatted search results
      def execute(query:, count: 5)
        return error("Web search requires BRAVE_API_KEY environment variable") unless api_key

        count = [[count, 1].max, 20].min

        response = client.get do |req|
          req.params["q"] = query
          req.params["count"] = count
        end

        return error("Search failed: #{response.status}") unless response.success?

        data = JSON.parse(response.body)
        format_results(data, query)
      rescue Faraday::Error => e
        error("Search request failed: #{e.message}")
      rescue JSON::ParserError
        error("Failed to parse search results")
      end

      private

      # Get the Brave Search API key from context or environment
      # @return [String, nil]
      def api_key
        @context[:brave_api_key] || ENV.fetch("BRAVE_API_KEY", nil)
      end

      # Build or access the Faraday HTTP client for Brave API
      # @return [Faraday::Connection]
      def client
        @client ||= Faraday.new(url: BRAVE_API_URL) do |f|
          f.headers["Accept"] = "application/json"
          f.headers["X-Subscription-Token"] = api_key
          f.adapter Faraday.default_adapter
        end
      end

      # Format search response data into readable output
      # @param data [Hash] parsed JSON response from Brave API
      # @param query [String] original search query
      # @return [String] formatted search results
      def format_results(data, query)
        results = data.dig("web", "results") || []

        return "No results found for: #{query}" if results.empty?

        output = ["Search results for: #{query}\n"]

        results.each_with_index do |result, idx|
          output << format_result(result, idx + 1)
        end

        output.join("\n")
      end

      # Format a single search result entry
      # @param result [Hash] search result with title, url, and description
      # @param index [Integer] result number for display
      # @return [String] formatted result entry
      def format_result(result, index)
        title = result["title"] || "Untitled"
        url = result["url"] || ""
        description = result["description"] || ""

        <<~RESULT
          #{index}. #{title}
             URL: #{url}
             #{description[0..300]}
        RESULT
      end
    end
  end
end
