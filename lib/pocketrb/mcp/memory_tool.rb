# frozen_string_literal: true

module Pocketrb
  module MCP
    # Tool for interacting with memory via MCP
    class MemoryTool < Tools::Base
      # Initialize memory tool
      # @param context [Hash] Context hash containing :mcp_client (defaults to empty hash)
      def initialize(context = {})
        super
        @client = context[:mcp_client] || Client.new
      end

# Tool name
      # @return [String] Tool identifier
      def name
        "memory"
      end

# Tool description
      # @return [String] Human-readable description
      def description
        "Interact with long-term memory. Search for relevant information or store new knowledge for future reference."
      end

# Tool parameters schema
      # @return [Hash] JSON schema
      def parameters
        {
          type: "object",
          properties: {
            action: {
              type: "string",
              enum: %w[search store],
              description: "Action to perform: 'search' to find information, 'store' to save new knowledge"
            },
            query: {
              type: "string",
              description: "For search: the query to search for"
            },
            content: {
              type: "string",
              description: "For store: the content to save to memory"
            },
            tags: {
              type: "array",
              items: { type: "string" },
              description: "For store: tags to associate with the content"
            },
            limit: {
              type: "integer",
              description: "For search: maximum number of results (default: 5)"
            }
          },
          required: ["action"]
        }
      end

# Check if MCP client is available
      # @return [Boolean] True if client can connect
      def available?
        @client.connected? || @client.connect
      rescue StandardError
        false
      end

      # Execute memory operation
      # @param action [String] Action to perform ("search" or "store")
      # @param query [String, nil] Search query (for search action)
      # @param content [String, nil] Content to store (for store action)
      # @param tags [Array<String>, nil] Tags to associate with content (for store action)
      # @param limit [Integer] Maximum search results (defaults to 5)
      # @return [String] JSON result of operation
      def execute(action:, query: nil, content: nil, tags: nil, limit: 5)
        case action
        when "search"
          execute_search(query, limit)
        when "store"
          execute_store(content, tags)
        else
          error("Unknown action: #{action}. Use 'search' or 'store'.")
        end
      end

      private

      def execute_search(query, limit)
        return error("Query is required for search") if query.nil? || query.empty?

        results = @client.search(query: query, limit: limit)

        return "No relevant memories found for: #{query}" if results.nil? || results.empty?

        format_search_results(results, query)
      rescue MCPError => e
        error("Memory search failed: #{e.message}")
      end

      def execute_store(content, tags)
        return error("Content is required for store") if content.nil? || content.empty?

        metadata = {}
        metadata[:tags] = tags if tags && !tags.empty?
        metadata[:timestamp] = Time.now.iso8601
        metadata[:source] = "pocketrb"

        result = @client.store(content: content, metadata: metadata)

        if result
          success("Stored to memory: #{content[0..100]}#{"..." if content.length > 100}")
        else
          error("Failed to store to memory")
        end
      rescue MCPError => e
        error("Memory store failed: #{e.message}")
      end

      def format_search_results(results, query)
        output = ["Memory search results for: #{query}\n"]

        if results.is_a?(String)
          # Direct text response from MCP
          output << results
        elsif results.is_a?(Array)
          results.each_with_index do |result, idx|
            output << format_result(result, idx + 1)
          end
        elsif results.is_a?(Hash) && results["results"]
          results["results"].each_with_index do |result, idx|
            output << format_result(result, idx + 1)
          end
        end

        output.join("\n")
      end

      def format_result(result, index)
        content = result["content"] || result["text"] || result.to_s
        score = result["score"]
        tags = result["tags"] || result.dig("metadata", "tags")

        parts = ["#{index}. #{content[0..500]}"]
        parts << "   Score: #{score.round(3)}" if score
        parts << "   Tags: #{tags.join(", ")}" if tags && !tags.empty?

        parts.join("\n")
      end
    end
  end
end
