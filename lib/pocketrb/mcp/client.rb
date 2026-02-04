# frozen_string_literal: true

require "faraday"
require "json"
require "securerandom"

module Pocketrb
  module MCP
    # MCP client for connecting to MCP HTTP Bridge
    # Implements JSON-RPC 2.0 protocol for MCP communication
    class Client
      DEFAULT_ENDPOINT = "http://localhost:7878"
      TIMEOUT = 30

      attr_reader :endpoint, :connected

      def initialize(endpoint: nil)
        @endpoint = endpoint || ENV["MCP_ENDPOINT"] || DEFAULT_ENDPOINT
        @connected = false
        @request_id = 0
      end

      # Initialize the MCP connection
      def connect
        response = rpc_call("initialize", {
                              protocolVersion: "2024-11-05",
                              capabilities: {
                                tools: {}
                              },
                              clientInfo: {
                                name: "pocketrb",
                                version: Pocketrb::VERSION
                              }
                            })

        @connected = !response["result"].nil?
        @server_info = response.dig("result", "serverInfo")
        @capabilities = response.dig("result", "capabilities")

        Pocketrb.logger.info("MCP connected to #{@server_info&.dig("name") || "server"}")
        @connected
      rescue StandardError => e
        Pocketrb.logger.warn("MCP connection failed: #{e.message}")
        @connected = false
      end

      # List available tools from MCP server
      def list_tools
        ensure_connected!

        response = rpc_call("tools/list", {})
        response.dig("result", "tools") || []
      end

      # Call a tool on the MCP server
      def call_tool(name:, arguments: {})
        ensure_connected!

        response = rpc_call("tools/call", {
                              name: name,
                              arguments: arguments
                            })

        raise MCPError, "Tool call failed: #{response["error"]["message"]}" if response["error"]

        response.dig("result", "content")&.first&.dig("text")
      end

      # Search memory via MCP
      def search(query:, limit: 10)
        # Try MCP tool first
        if tool_available?("memory_search")
          call_tool(name: "memory_search", arguments: { query: query, limit: limit })
        else
          # Fall back to direct HTTP endpoint
          http_search(query, limit)
        end
      end

      # Store to memory via MCP
      def store(content:, metadata: {})
        # Try MCP tool first
        if tool_available?("memory_store")
          call_tool(name: "memory_store", arguments: { content: content, metadata: metadata })
        else
          # Fall back to direct HTTP endpoint
          http_store(content, metadata)
        end
      end

      # Check if connected
      def connected?
        @connected
      end

      # Disconnect from server
      def disconnect
        @connected = false
      end

      private

      def ensure_connected!
        return if @connected

        connect
        raise MCPError, "Not connected to MCP server" unless @connected
      end

      def rpc_call(method, params)
        @request_id += 1

        request_body = {
          jsonrpc: "2.0",
          id: @request_id,
          method: method,
          params: params
        }

        response = client.post("/rpc") do |req|
          req.body = request_body.to_json
        end

        raise MCPError, "RPC call failed: HTTP #{response.status}" unless response.success?

        JSON.parse(response.body)
      rescue Faraday::Error => e
        raise MCPError, "RPC connection error: #{e.message}"
      end

      def client
        @client ||= Faraday.new(url: @endpoint) do |f|
          f.headers["Content-Type"] = "application/json"
          f.options.timeout = TIMEOUT
          f.adapter Faraday.default_adapter
        end
      end

      def tool_available?(name)
        @tools ||= list_tools
        @tools.any? { |t| t["name"] == name }
      rescue MCPError
        false
      end

      # Direct HTTP endpoints (fallback when not using MCP tools)
      def http_search(query, limit)
        response = client.post("/search") do |req|
          req.body = { query: query, limit: limit }.to_json
        end

        return nil unless response.success?

        JSON.parse(response.body)
      rescue StandardError
        nil
      end

      def http_store(content, metadata)
        response = client.post("/store") do |req|
          req.body = { content: content, metadata: metadata }.to_json
        end

        return false unless response.success?

        true
      rescue StandardError
        false
      end
    end
  end
end
