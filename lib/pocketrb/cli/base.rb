# frozen_string_literal: true

require "thor"

module Pocketrb
  class CLI
    # Base class for CLI commands with common utilities
    class Base < Thor
      include Thor::Actions

      # Configures Thor to exit with error status on command failure
      # @return [Boolean] true to exit on failure
      def self.exit_on_failure?
        true
      end

      private

      # Set up logging based on verbose/quiet options
      def setup_logging
        if options[:verbose]
          Pocketrb.logger.level = Logger::DEBUG
        elsif options[:quiet]
          Pocketrb.logger.level = Logger::ERROR
        end
      end

      # Resolve workspace directory from options or current directory
      # @return [Pathname] workspace path
      def resolve_workspace
        path = options[:workspace] || Dir.pwd
        Pathname.new(path).expand_path
      end

      # Resolve memory directory from options or workspace
      # @return [Pathname] memory directory path
      def resolve_memory_dir
        path = options[:memory_dir] || options[:workspace] || Dir.pwd
        Pathname.new(path).expand_path
      end

      # Create provider instance from config
      # @param config [Config] configuration object
      # @return [Providers::Base] provider instance
      def create_provider(config)
        provider_name = config[:provider]&.to_sym || :anthropic
        Providers::Registry.get(provider_name, config.provider_config)
      end

      # Handle cron job execution
      # @param agent_loop [Agent::Loop] agent loop instance
      # @param bus [Bus::MessageBus] message bus
      # @param job [Cron::Job] cron job to execute
      def handle_cron_job(agent_loop, bus, job)
        if job.payload.deliver
          # Deliver message directly to channel
          outbound = Pocketrb::Bus::OutboundMessage.new(
            channel: job.payload.channel&.to_sym || :cli,
            chat_id: job.payload.to || "cron",
            content: job.payload.message
          )
          bus.publish_outbound(outbound)
        else
          # Process as agent task
          msg = Pocketrb::Bus::InboundMessage.new(
            channel: :cron,
            sender_id: "cron",
            chat_id: job.id,
            content: job.payload.message,
            metadata: { job_id: job.id, job_name: job.name }
          )
          agent_loop.process_message(msg)
        end
      end

      # Process heartbeat message
      # @param agent_loop [Agent::Loop] agent loop instance
      # @param prompt [String] heartbeat prompt
      # @return [String, nil] response content
      def process_heartbeat(agent_loop, prompt)
        msg = Pocketrb::Bus::InboundMessage.new(
          channel: :heartbeat,
          sender_id: "heartbeat",
          chat_id: "heartbeat",
          content: prompt
        )
        response = agent_loop.process_message(msg)
        response&.content
      end

      # Default TOOLS.md content for new workspaces
      # @return [String] markdown content
      def default_tools_content
        <<~MD
          # Tools

          This document describes the tools and skills available in this workspace.

          ## Built-in Tools

          - **read_file**: Read file contents
          - **write_file**: Write content to a file
          - **edit_file**: Edit a file with search/replace
          - **list_dir**: List directory contents
          - **exec**: Execute shell commands
          - **web_search**: Search the web
          - **web_fetch**: Fetch web page content
          - **think**: Internal reasoning tool
          - **plan**: Create and manage execution plans
          - **memory**: Search and store in long-term memory

          ## Skills

          Create custom skills in the `skills/` directory.
        MD
      end
    end
  end
end
