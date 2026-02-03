# frozen_string_literal: true

require "faraday"
require "json"

module Pocketrb
  module Tools
    # Search the web using Brave Search API
    class WebSearch < Base
      BRAVE_API_URL = "https://api.search.brave.com/res/v1/web/search"

      def name
        "web_search"
      end

      def description
        "Search the web for information. Returns relevant search results with titles, URLs, and descriptions."
      end

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

      def available?
        api_key && !api_key.empty?
      end

      def execute(query:, count: 5)
        unless api_key
          return error("Web search requires BRAVE_API_KEY environment variable")
        end

        count = [[count, 1].max, 20].min

        response = client.get do |req|
          req.params["q"] = query
          req.params["count"] = count
        end

        unless response.success?
          return error("Search failed: #{response.status}")
        end

        data = JSON.parse(response.body)
        format_results(data, query)
      rescue Faraday::Error => e
        error("Search request failed: #{e.message}")
      rescue JSON::ParserError
        error("Failed to parse search results")
      end

      private

      def api_key
        @context[:brave_api_key] || ENV["BRAVE_API_KEY"]
      end

      def client
        @client ||= Faraday.new(url: BRAVE_API_URL) do |f|
          f.headers["Accept"] = "application/json"
          f.headers["X-Subscription-Token"] = api_key
          f.adapter Faraday.default_adapter
        end
      end

      def format_results(data, query)
        results = data.dig("web", "results") || []

        if results.empty?
          return "No results found for: #{query}"
        end

        output = ["Search results for: #{query}\n"]

        results.each_with_index do |result, idx|
          output << format_result(result, idx + 1)
        end

        output.join("\n")
      end

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
