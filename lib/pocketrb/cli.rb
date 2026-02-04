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

    class_option :workspace, type: :string, aliases: "-w",
                             desc: "Workspace directory for file access (default: current directory)"
    class_option :memory_dir, type: :string, aliases: "-M",
                              desc: "Memory/persona directory (default: same as workspace)"
    class_option :verbose, type: :boolean, aliases: "-v",
                           desc: "Enable verbose output"
    class_option :quiet, type: :boolean, aliases: "-q",
                         desc: "Suppress non-essential output"

    desc "start", "Start the agent in continuous mode"
    option :model, type: :string, aliases: "-m", desc: "Model to use"
    option :provider, type: :string, aliases: "-p", desc: "LLM provider (anthropic, openrouter)"
    option :channel, type: :string, aliases: "-c", default: "cli", desc: "Channel to connect to"
    # Starts the agent in continuous mode with CLI channel
    # @return [void]
    def start
      setup_logging
      workspace = resolve_workspace
      memory_dir = resolve_memory_dir

      config = Config.load(memory_dir)
      config[:model] = options[:model] if options[:model]
      config[:provider] = options[:provider] if options[:provider]

      provider = create_provider(config)
      bus = Bus::MessageBus.new

      agent_loop = Agent::Loop.new(
        bus: bus,
        provider: provider,
        workspace: workspace,
        memory_dir: memory_dir,
        model: config[:model],
        max_iterations: config[:max_iterations],
        mcp_endpoint: config[:mcp_endpoint]
      )

      say "Pocketrb started with #{config[:provider]}/#{config[:model]}", :green
      say "Workspace: #{workspace}"
      say "Memory: #{memory_dir}" if memory_dir != workspace
      say "Press Ctrl+C to stop\n"

      # Start CLI channel
      channel = Channels::CLI.new(bus: bus)

      Async do
        agent_loop.run
        channel.run
      end
    rescue Interrupt
      say "\nShutting down...", :yellow
    end

    desc "chat", "Interactive chat mode (single session)"
    option :model, type: :string, aliases: "-m", desc: "Model to use"
    option :provider, type: :string, aliases: "-p", desc: "LLM provider"
    option :system_prompt, type: :string, aliases: "-s", desc: "Custom system prompt"
    # Starts an interactive chat session with the agent
    # @return [void]
    def chat
      setup_logging
      workspace = resolve_workspace
      memory_dir = resolve_memory_dir

      config = Config.load(memory_dir)
      config[:model] = options[:model] if options[:model]
      config[:provider] = options[:provider] if options[:provider]

      provider = create_provider(config)
      bus = Bus::MessageBus.new

      agent_loop = Agent::Loop.new(
        bus: bus,
        provider: provider,
        workspace: workspace,
        memory_dir: memory_dir,
        model: config[:model],
        system_prompt: options[:system_prompt],
        mcp_endpoint: config[:mcp_endpoint]
      )

      say "Pocketrb Chat - #{config[:model]}", :green
      say "Memory: #{memory_dir}" if memory_dir != workspace
      say "Type 'exit' or 'quit' to end session\n"

      Async do
        # Simple REPL
        loop do
          print "\n> "
          input = $stdin.gets&.chomp
          break if input.nil? || %w[exit quit].include?(input.downcase)

          next if input.empty?

          msg = Bus::InboundMessage.new(
            channel: :cli,
            sender_id: "user",
            chat_id: "chat",
            content: input
          )

          response = agent_loop.process_message(msg)
          puts "\n#{response.content}" if response
        end
      end

      say "\nGoodbye!", :yellow
    end

    desc "config SUBCOMMAND", "Manage configuration"
    subcommand "config", Class.new(Thor) {
      desc "show", "Show current configuration"
      def show
        workspace = options[:workspace] || Dir.pwd
        config = Config.load(workspace)

        say "Configuration for #{workspace}:"
        config.to_h.each do |key, value|
          # Don't show API keys
          display_value = key.to_s.include?("api_key") ? "[REDACTED]" : value
          say "  #{key}: #{display_value}"
        end
      end

      desc "set KEY VALUE", "Set a configuration value"
      def set(key, value)
        workspace = options[:workspace] || Dir.pwd
        config = Config.load(workspace)

        # Type conversion
        value = case value
                when /^\d+$/ then value.to_i
                when /^\d+\.\d+$/ then value.to_f
                when "true" then true
                when "false" then false
                else value
                end

        config.set(key, value)
        say "Set #{key} = #{value}", :green
      end

      desc "get KEY", "Get a configuration value"
      def get(key)
        workspace = options[:workspace] || Dir.pwd
        config = Config.load(workspace)

        value = config[key]
        if value
          say "#{key}: #{value}"
        else
          say "Key '#{key}' not found", :yellow
        end
      end
    }

    desc "init", "Initialize a new Pocketrb workspace"
    # Initializes a new Pocketrb workspace with config and default structure
    # @return [void]
    def init
      workspace = resolve_workspace
      config_dir = workspace.join(".pocketrb")

      if config_dir.exist?
        say "Workspace already initialized at #{workspace}", :yellow
        return
      end

      FileUtils.mkdir_p(config_dir)
      FileUtils.mkdir_p(workspace.join("skills"))

      Config.new(workspace: workspace).save!

      # Create default TOOLS.md
      tools_file = workspace.join("TOOLS.md")
      File.write(tools_file, default_tools_content) unless tools_file.exist?

      say "Initialized Pocketrb workspace at #{workspace}", :green
      say "  - Created .pocketrb/config.yml"
      say "  - Created skills/"
      say "\nNext steps:"
      say "  1. Set your API key: export ANTHROPIC_API_KEY=your-key"
      say "  2. Start chatting: pocketrb chat"
    end

    desc "version", "Show version"
    # Displays the current Pocketrb version
    # @return [void]
    def version
      say "Pocketrb #{VERSION}"
    end

    desc "skills", "List available skills"
    # Lists all available skills from the workspace skills directory
    # @return [void]
    def skills
      workspace = resolve_workspace
      loader = Skills::Loader.new(workspace: workspace)

      skills = loader.list_skills
      if skills.empty?
        say "No skills found in #{workspace}/skills/", :yellow
        return
      end

      say "Available skills:"
      skills.each do |skill|
        flags = []
        flags << "always" if skill.always?
        flags << "triggers: #{skill.triggers.join(", ")}" if skill.triggers.any?

        flag_str = flags.any? ? " (#{flags.join(", ")})" : ""
        say "  - #{skill.name}: #{skill.description}#{flag_str}"
      end
    end

    desc "plans", "List active plans"
    # Lists all active execution plans in the workspace
    # @return [void]
    def plans
      workspace = resolve_workspace
      manager = Planning::Manager.new(workspace: workspace)

      plans = manager.list_plans
      if plans.empty?
        say "No plans found", :yellow
        return
      end

      plans.each do |plan|
        say "\n#{plan.to_markdown}"
      end
    end

    desc "qmd SUBCOMMAND", "Manage QMD memory"
    subcommand "qmd", Class.new(Thor) {
      desc "status", "Check QMD connection status"
      def status
        workspace = Pathname.new(options[:workspace] || Dir.pwd).expand_path
        config = Config.load(workspace)
        endpoint = config[:mcp_endpoint]

        say "QMD Memory Status"
        say "  Endpoint: #{endpoint}"

        qmd = Memory::QMD.new(workspace: workspace, endpoint: endpoint)

        if qmd.connect
          say "  Status: Connected", :green
          say "  Server: #{qmd.client.instance_variable_get(:@server_info)&.dig("name") || "unknown"}"
        else
          say "  Status: Not connected", :yellow
          say "  Make sure QMD server is running at #{endpoint}"
        end
      end

      desc "search QUERY", "Search memory"
      option :limit, type: :numeric, default: 5, desc: "Max results"
      def search(query)
        workspace = Pathname.new(options[:workspace] || Dir.pwd).expand_path
        config = Config.load(workspace)

        qmd = Memory::QMD.new(workspace: workspace, endpoint: config[:mcp_endpoint])
        qmd.connect

        results = qmd.search(query, limit: options[:limit])

        say "Search results for: #{query}\n"

        if results[:qmd].any?
          say "QMD results:", :green
          results[:qmd].each_with_index do |r, i|
            say "  #{i + 1}. #{r[:content][0..150]}..."
            say "     Score: #{r[:score].round(3)}" if r[:score]
          end
        else
          say "  No QMD results (server may not be connected)", :yellow
        end

        if results[:local] && !results[:local].empty?
          say "\nLocal memory:", :green
          say "  #{results[:local][0..300]}"
        end

        return unless results[:daily]

        say "\nDaily notes:", :green
        say "  #{results[:daily][0..300]}"
      end

      desc "store CONTENT", "Store content to memory"
      option :topic, type: :string, desc: "Topic/category for the content"
      option :tags, type: :array, desc: "Tags to associate"
      def store(content)
        workspace = Pathname.new(options[:workspace] || Dir.pwd).expand_path
        config = Config.load(workspace)

        qmd = Memory::QMD.new(workspace: workspace, endpoint: config[:mcp_endpoint])
        qmd.connect

        metadata = {}
        metadata[:topic] = options[:topic] if options[:topic]
        metadata[:tags] = options[:tags] if options[:tags]

        if qmd.store(content, metadata: metadata)
          say "Stored to memory: #{content[0..100]}...", :green
        else
          say "Failed to store (QMD may not be connected, but local storage succeeded)", :yellow
        end
      end

      desc "summary", "Show memory summary"
      def summary
        workspace = Pathname.new(options[:workspace] || Dir.pwd).expand_path
        config = Config.load(workspace)

        qmd = Memory::QMD.new(workspace: workspace, endpoint: config[:mcp_endpoint])
        qmd.connect

        say qmd.summary
      end

      desc "sync", "Sync local memory to QMD"
      def sync
        workspace = Pathname.new(options[:workspace] || Dir.pwd).expand_path
        config = Config.load(workspace)

        qmd = Memory::QMD.new(workspace: workspace, endpoint: config[:mcp_endpoint])

        unless qmd.connect
          say "Cannot sync: QMD not connected", :red
          exit 1
        end

        count = qmd.sync_to_qmd
        say "Synced #{count} items to QMD", :green
      end
    }

    desc "telegram", "Run as a Telegram bot"
    option :model, type: :string, aliases: "-m", desc: "Model to use"
    option :provider, type: :string, aliases: "-p", desc: "LLM provider"
    option :token, type: :string, aliases: "-t", desc: "Telegram bot token (or TELEGRAM_BOT_TOKEN env)"
    option :allowed_users, type: :array, aliases: "-u", desc: "Allowed usernames or user IDs"
    option :enable_cron, type: :boolean, default: true, desc: "Enable cron/scheduling service"
    option :autonomous, type: :boolean, default: false, desc: "Skip permission prompts (for sandboxed environments)"
    # Runs the agent as a Telegram bot
    # @return [void]
    def telegram
      setup_logging
      workspace = resolve_workspace
      memory_dir = resolve_memory_dir

      token = options[:token] || ENV.fetch("TELEGRAM_BOT_TOKEN", nil)
      unless token
        say "Error: Telegram bot token required", :red
        say "Set TELEGRAM_BOT_TOKEN env var or use --token", :yellow
        exit 1
      end

      config = Config.load(memory_dir)
      config[:model] = options[:model] if options[:model]
      config[:provider] = options[:provider] if options[:provider]
      config[:autonomous] = options[:autonomous] if options[:autonomous]

      provider = create_provider(config)
      bus = Bus::MessageBus.new

      agent_loop = Agent::Loop.new(
        bus: bus,
        provider: provider,
        workspace: workspace,
        memory_dir: memory_dir,
        model: config[:model],
        max_iterations: config[:max_iterations]
      )

      # Enable cron service for proactive scheduling
      cron_service = nil
      if options[:enable_cron]
        cron_store = memory_dir.join(".pocketrb", "data", "cron", "jobs.json")
        cron_service = Cron::Service.new(
          store_path: cron_store,
          on_job: ->(job) { handle_cron_job(agent_loop, bus, job) }
        )
        agent_loop.tools.update_context(cron_service: cron_service)
      end

      say "Starting Pocketrb Telegram Bot", :green
      say "Provider: #{config[:provider]}/#{config[:model]}"
      say "Workspace: #{workspace}"
      say "Memory: #{memory_dir}" if memory_dir != workspace
      say "Cron: #{options[:enable_cron] ? "enabled" : "disabled"}"
      say "Autonomous: #{options[:autonomous] ? "yes (claude_cli only)" : "no"}" if options[:autonomous]
      say "Press Ctrl+C to stop\n"

      channel = Channels::Telegram.new(
        bus: bus,
        token: token,
        allowed_users: options[:allowed_users]
      )

      # Set up status context for /status command
      channel.status_context = {
        provider: provider,
        model: config[:model],
        sessions: agent_loop.sessions,
        memory_dir: memory_dir,
        cron_service: cron_service
      }

      Async do
        agent_loop.run
        channel.run
        cron_service&.start
      end
    rescue Interrupt
      say "\nShutting down Telegram bot...", :yellow
      cron_service&.stop
    end

    desc "whatsapp", "Run as a WhatsApp bot (requires Node.js bridge)"
    option :model, type: :string, aliases: "-m", desc: "Model to use"
    option :provider, type: :string, aliases: "-p", desc: "LLM provider"
    option :bridge_url, type: :string, default: "ws://localhost:3001", desc: "WhatsApp bridge WebSocket URL"
    option :allowed_users, type: :array, aliases: "-u", desc: "Allowed phone numbers"
    # Runs the agent as a WhatsApp bot using a WebSocket bridge
    # @return [void]
    def whatsapp
      setup_logging
      workspace = resolve_workspace
      memory_dir = resolve_memory_dir

      config = Config.load(memory_dir)
      config[:model] = options[:model] if options[:model]
      config[:provider] = options[:provider] if options[:provider]

      provider = create_provider(config)
      bus = Bus::MessageBus.new

      agent_loop = Agent::Loop.new(
        bus: bus,
        provider: provider,
        workspace: workspace,
        memory_dir: memory_dir,
        model: config[:model],
        max_iterations: config[:max_iterations]
      )

      say "Starting Pocketrb WhatsApp Bot", :green
      say "Provider: #{config[:provider]}/#{config[:model]}"
      say "Bridge: #{options[:bridge_url]}"
      say "Workspace: #{workspace}"
      say "Memory: #{memory_dir}" if memory_dir != workspace
      say "Press Ctrl+C to stop\n"

      channel = Channels::WhatsApp.new(
        bus: bus,
        bridge_url: options[:bridge_url],
        allowed_users: options[:allowed_users]
      )

      Async do
        agent_loop.run
        channel.run
      end
    rescue Interrupt
      say "\nShutting down WhatsApp bot...", :yellow
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
    # Starts the gateway with all configured services (Telegram, WhatsApp, cron, heartbeat)
    # @return [void]
    def gateway
      setup_logging
      workspace = resolve_workspace
      memory_dir = resolve_memory_dir

      config = Config.load(memory_dir)
      config[:model] = options[:model] if options[:model]
      config[:provider] = options[:provider] if options[:provider]
      config[:autonomous] = options[:autonomous] if options[:autonomous]

      provider = create_provider(config)
      bus = Bus::MessageBus.new

      agent_loop = Agent::Loop.new(
        bus: bus,
        provider: provider,
        workspace: workspace,
        memory_dir: memory_dir,
        model: config[:model],
        max_iterations: config[:max_iterations]
      )

      say "Starting Pocketrb Gateway", :green
      say "Provider: #{config[:provider]}/#{config[:model]}"
      say "Workspace: #{workspace}"
      say "Memory: #{memory_dir}" if memory_dir != workspace

      channels = []
      services = []

      # Start Telegram if token provided
      telegram_token = options[:telegram_token] || ENV.fetch("TELEGRAM_BOT_TOKEN", nil)
      if telegram_token
        channels << Channels::Telegram.new(
          bus: bus,
          token: telegram_token,
          allowed_users: options[:telegram_users]
        )
        say "  - Telegram: enabled"
      end

      # Start WhatsApp if bridge available
      if options[:whatsapp_bridge]
        channels << Channels::WhatsApp.new(
          bus: bus,
          bridge_url: options[:whatsapp_bridge],
          allowed_users: options[:whatsapp_users]
        )
        say "  - WhatsApp: enabled (#{options[:whatsapp_bridge]})"
      end

      # Start Cron service
      if options[:enable_cron]
        cron_store = memory_dir.join(".pocketrb", "data", "cron", "jobs.json")
        cron_service = Cron::Service.new(
          store_path: cron_store,
          on_job: ->(job) { handle_cron_job(agent_loop, bus, job) }
        )
        services << cron_service
        # Pass cron_service to tools so agent can manage jobs
        agent_loop.tools.update_context(cron_service: cron_service)
        say "  - Cron: enabled"
      end

      # Start Heartbeat service
      if options[:enable_heartbeat]
        heartbeat_service = Heartbeat::Service.new(
          workspace: workspace,
          interval: options[:heartbeat_interval],
          on_heartbeat: ->(prompt) { process_heartbeat(agent_loop, prompt) }
        )
        services << heartbeat_service
        say "  - Heartbeat: enabled (#{options[:heartbeat_interval]}s)"
      end

      # Set up status context for /status command on Telegram channels
      status_context = {
        provider: provider,
        model: config[:model],
        sessions: agent_loop.sessions,
        memory_dir: memory_dir,
        cron_service: cron_service
      }
      channels.each do |ch|
        ch.status_context = status_context if ch.respond_to?(:status_context=)
      end

      say "\nPress Ctrl+C to stop\n"

      Async do
        # Start agent loop
        agent_loop.run

        # Start all channels
        channels.each(&:run)

        # Start all services
        services.each(&:start)

        # Keep running
        sleep
      end
    rescue Interrupt
      say "\nShutting down gateway...", :yellow
      services.each(&:stop)
      channels.each(&:stop)
    end

    desc "cron SUBCOMMAND", "Manage scheduled jobs"
    subcommand "cron", Class.new(Thor) {
      desc "list", "List scheduled jobs"
      option :all, type: :boolean, aliases: "-a", desc: "Include disabled jobs"
      def list
        workspace = Pathname.new(options[:workspace] || Dir.pwd).expand_path
        cron_store = workspace.join(".pocketrb", "data", "cron", "jobs.json")

        service = Cron::Service.new(
          store_path: cron_store,
          on_job: ->(_) {}
        )

        jobs = service.list_jobs(include_disabled: options[:all])
        if jobs.empty?
          say "No scheduled jobs", :yellow
          return
        end

        say "Scheduled jobs:"
        jobs.each do |job|
          status = job.enabled ? "enabled" : "disabled"
          next_run = job.state.next_run_at_ms ? Time.at(job.state.next_run_at_ms / 1000).strftime("%Y-%m-%d %H:%M") : "never"
          say "  #{job.id}: #{job.name} [#{status}] - next: #{next_run}"
        end
      end

      desc "add", "Add a scheduled job"
      option :name, type: :string, required: true, desc: "Job name"
      option :message, type: :string, required: true, desc: "Message to process"
      option :every, type: :numeric, desc: "Run every N seconds"
      option :cron, type: :string, desc: "Cron expression (e.g., '0 9 * * *')"
      option :at, type: :string, desc: "Run once at ISO datetime"
      option :deliver, type: :boolean, default: false, desc: "Deliver to channel instead of processing"
      option :channel, type: :string, desc: "Target channel for delivery"
      option :to, type: :string, desc: "Target chat ID for delivery"
      def add
        workspace = Pathname.new(options[:workspace] || Dir.pwd).expand_path
        cron_store = workspace.join(".pocketrb", "data", "cron", "jobs.json")

        service = Cron::Service.new(
          store_path: cron_store,
          on_job: ->(_) {}
        )

        job = if options[:every]
                service.add_interval_job(
                  name: options[:name],
                  every: options[:every],
                  message: options[:message],
                  deliver: options[:deliver],
                  channel: options[:channel],
                  to: options[:to]
                )
              elsif options[:cron]
                service.add_cron_job(
                  name: options[:name],
                  cron: options[:cron],
                  message: options[:message],
                  deliver: options[:deliver],
                  channel: options[:channel],
                  to: options[:to]
                )
              elsif options[:at]
                at_time = Time.parse(options[:at])
                service.add_one_time_job(
                  name: options[:name],
                  at: at_time,
                  message: options[:message],
                  deliver: options[:deliver],
                  channel: options[:channel],
                  to: options[:to]
                )
              else
                say "Error: Must specify --every, --cron, or --at", :red
                exit 1
              end

        say "Created job: #{job.id} (#{job.name})", :green
      end

      desc "remove JOB_ID", "Remove a scheduled job"
      def remove(job_id)
        workspace = Pathname.new(options[:workspace] || Dir.pwd).expand_path
        cron_store = workspace.join(".pocketrb", "data", "cron", "jobs.json")

        service = Cron::Service.new(
          store_path: cron_store,
          on_job: ->(_) {}
        )

        if service.remove_job(job_id)
          say "Removed job: #{job_id}", :green
        else
          say "Job not found: #{job_id}", :red
        end
      end

      desc "enable JOB_ID", "Enable a scheduled job"
      def enable(job_id)
        workspace = Pathname.new(options[:workspace] || Dir.pwd).expand_path
        cron_store = workspace.join(".pocketrb", "data", "cron", "jobs.json")

        service = Cron::Service.new(
          store_path: cron_store,
          on_job: ->(_) {}
        )

        if service.enable_job(job_id, enabled: true)
          say "Enabled job: #{job_id}", :green
        else
          say "Job not found: #{job_id}", :red
        end
      end

      desc "disable JOB_ID", "Disable a scheduled job"
      def disable(job_id)
        workspace = Pathname.new(options[:workspace] || Dir.pwd).expand_path
        cron_store = workspace.join(".pocketrb", "data", "cron", "jobs.json")

        service = Cron::Service.new(
          store_path: cron_store,
          on_job: ->(_) {}
        )

        if service.enable_job(job_id, enabled: false)
          say "Disabled job: #{job_id}", :green
        else
          say "Job not found: #{job_id}", :red
        end
      end

      desc "trigger JOB_ID", "Trigger a job manually"
      def trigger(_job_id)
        say "Manual job execution requires running gateway", :yellow
        say "Use 'pocketrb gateway' and the job will be executed", :yellow
      end
    }

    private

    def handle_cron_job(agent_loop, bus, job)
      if job.payload.deliver
        # Deliver message directly to channel
        outbound = Bus::OutboundMessage.new(
          channel: job.payload.channel&.to_sym || :cli,
          chat_id: job.payload.to || "cron",
          content: job.payload.message
        )
        bus.publish_outbound(outbound)
      else
        # Process as agent task
        msg = Bus::InboundMessage.new(
          channel: :cron,
          sender_id: "cron",
          chat_id: job.id,
          content: job.payload.message,
          metadata: { job_id: job.id, job_name: job.name }
        )
        agent_loop.process_message(msg)
      end
    end

    def process_heartbeat(agent_loop, prompt)
      msg = Bus::InboundMessage.new(
        channel: :heartbeat,
        sender_id: "heartbeat",
        chat_id: "heartbeat",
        content: prompt
      )
      response = agent_loop.process_message(msg)
      response&.content
    end

    def setup_logging
      if options[:verbose]
        Pocketrb.logger.level = Logger::DEBUG
      elsif options[:quiet]
        Pocketrb.logger.level = Logger::ERROR
      end
    end

    def resolve_workspace
      path = options[:workspace] || Dir.pwd
      Pathname.new(path).expand_path
    end

    def resolve_memory_dir
      path = options[:memory_dir] || options[:workspace] || Dir.pwd
      Pathname.new(path).expand_path
    end

    def create_provider(config)
      provider_name = config[:provider]&.to_sym || :anthropic
      Providers::Registry.get(provider_name, config.provider_config)
    end

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
