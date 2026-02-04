# frozen_string_literal: true

require "thor"

# Main namespace for Pocketrb gem
module Pocketrb
  # Command-line interface
  class CLI < Thor
    include Thor::Actions

    # Configures Thor to exit with error status on command failure
    # @return [Boolean] true to exit on failure
    def self.exit_on_failure?
      true
    end

    # Global options available to all commands
    class_option :workspace, type: :string, aliases: "-w",
                             desc: "Workspace directory for file access (default: current directory)"
    class_option :memory_dir, type: :string, aliases: "-M",
                              desc: "Memory/persona directory (default: same as workspace)"
    class_option :verbose, type: :boolean, aliases: "-v",
                           desc: "Enable verbose output"
    class_option :quiet, type: :boolean, aliases: "-q",
                         desc: "Suppress non-essential output"

    # Register subcommands
    desc "config SUBCOMMAND", "Manage configuration"
    subcommand "config", CLI::Config

    desc "cron SUBCOMMAND", "Manage scheduled jobs"
    subcommand "cron", CLI::Cron

    # Register individual commands by delegating to their classes
    desc "version", "Show version"
    def version
      invoke CLI::Version, :call, [], options
    end

    desc "skills", "List available skills"
    def skills
      invoke CLI::Skills, :call, [], options
    end

    desc "plans", "List active plans"
    def plans
      invoke CLI::Plans, :call, [], options
    end

    desc "init", "Initialize a new Pocketrb workspace"
    def init
      invoke CLI::Init, :call, [], options
    end

    desc "chat", "Interactive chat mode (single session)"
    option :model, type: :string, aliases: "-m", desc: "Model to use"
    option :provider, type: :string, aliases: "-p", desc: "LLM provider"
    option :system_prompt, type: :string, aliases: "-s", desc: "Custom system prompt"
    def chat
      invoke CLI::Chat, :call, [], options
    end

    desc "start", "Start the agent in continuous mode"
    option :model, type: :string, aliases: "-m", desc: "Model to use"
    option :provider, type: :string, aliases: "-p", desc: "LLM provider (anthropic, openrouter)"
    option :channel, type: :string, aliases: "-c", default: "cli", desc: "Channel to connect to"
    def start
      invoke CLI::Start, :call, [], options
    end

    desc "telegram", "Run as a Telegram bot"
    option :model, type: :string, aliases: "-m", desc: "Model to use"
    option :provider, type: :string, aliases: "-p", desc: "LLM provider"
    option :token, type: :string, aliases: "-t", desc: "Telegram bot token (or TELEGRAM_BOT_TOKEN env)"
    option :allowed_users, type: :array, aliases: "-u", desc: "Allowed usernames or user IDs"
    option :enable_cron, type: :boolean, default: true, desc: "Enable cron/scheduling service"
    option :autonomous, type: :boolean, default: false, desc: "Skip permission prompts (for sandboxed environments)"
    def telegram
      invoke CLI::Telegram, :call, [], options
    end

    desc "whatsapp", "Run as a WhatsApp bot (requires Node.js bridge)"
    option :model, type: :string, aliases: "-m", desc: "Model to use"
    option :provider, type: :string, aliases: "-p", desc: "LLM provider"
    option :bridge_url, type: :string, default: "ws://localhost:3001", desc: "WhatsApp bridge WebSocket URL"
    option :allowed_users, type: :array, aliases: "-u", desc: "Allowed phone numbers"
    def whatsapp
      invoke CLI::WhatsApp, :call, [], options
    end

    desc "gateway", "Start the gateway with all services"
    option :model, type: :string, aliases: "-m", desc: "Model to use"
    option :provider, type: :string, aliases: "-p", desc: "LLM provider"
    option :telegram_token, type: :string, desc: "Telegram bot token"
    option :telegram_users, type: :array, desc: "Allowed Telegram users"
    option :whatsapp_bridge, type: :string, default: "ws://localhost:3001", desc: "WhatsApp bridge URL"
    option :whatsapp_users, type: :array, desc: "Allowed WhatsApp numbers"
    option :heartbeat_interval, type: :numeric, default: 1800, desc: "Heartbeat interval in seconds"
    option :enable_cron, type: :boolean, default: true, desc: "Enable cron service"
    option :enable_heartbeat, type: :boolean, default: true, desc: "Enable heartbeat service"
    option :autonomous, type: :boolean, default: false, desc: "Skip permission prompts (for sandboxed environments)"
    def gateway
      invoke CLI::Gateway, :call, [], options
    end
  end
end
