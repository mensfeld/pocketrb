# frozen_string_literal: true

require "yaml"

module Pocketrb
  # Configuration management
  class Config
    CONFIG_FILE = "config.yml"
    CONFIG_DIR = ".pocketrb"

    DEFAULTS = {
      provider: "anthropic",
      model: "claude-sonnet-4-20250514",
      max_iterations: 50,
      heartbeat_interval: 1800, # 30 minutes (1800s)
      mcp_endpoint: "http://localhost:7878",
      log_level: "info",
      session_history_limit: 100,
      tool_timeout: 120
    }.freeze

    attr_reader :workspace, :data

    def initialize(workspace: nil)
      @workspace = workspace ? Pathname.new(workspace) : nil
      @data = DEFAULTS.dup
      load_config!
    end

    # Get a config value
    def [](key)
      @data[key.to_sym] || @data[key.to_s]
    end

    # Set a config value
    def []=(key, value)
      @data[key.to_sym] = value
    end

    # Get with default
    def get(key, default = nil)
      self[key] || default
    end

    # Set a value and save
    def set(key, value)
      self[key] = value
      save!
    end

    # Check if key exists
    def key?(key)
      @data.key?(key.to_sym) || @data.key?(key.to_s)
    end

    # Get provider configuration
    def provider_config
      # Warn about deprecated API key environment variables
      warn_env_deprecated("ANTHROPIC_API_KEY", "anthropic_api_key") if ENV["ANTHROPIC_API_KEY"]
      warn_env_deprecated("OPENROUTER_API_KEY", "openrouter_api_key") if ENV["OPENROUTER_API_KEY"]
      warn_env_deprecated("OPENAI_API_KEY", "openai_api_key") if ENV["OPENAI_API_KEY"]
      warn_env_deprecated("BRAVE_API_KEY", "brave_api_key") if ENV["BRAVE_API_KEY"]

      {
        anthropic_api_key: ENV["ANTHROPIC_API_KEY"] || self[:anthropic_api_key],
        openrouter_api_key: ENV["OPENROUTER_API_KEY"] || self[:openrouter_api_key],
        openai_api_key: ENV["OPENAI_API_KEY"] || self[:openai_api_key],
        brave_api_key: ENV["BRAVE_API_KEY"] || self[:brave_api_key],
        model: self[:model],
        autonomous: self[:autonomous],
        dangerously_skip_permissions: self[:dangerously_skip_permissions],
        permission_mode: self[:permission_mode],
        system_prompt: self[:system_prompt]
      }.compact
    end

    # Save configuration
    def save!
      return unless @workspace

      config_dir = @workspace.join(CONFIG_DIR)
      FileUtils.mkdir_p(config_dir)

      config_file = config_dir.join(CONFIG_FILE)
      File.write(config_file, @data.to_yaml)

      Pocketrb.logger.debug("Saved config to #{config_file}")
    end

    # Reload configuration
    def reload!
      @data = DEFAULTS.dup
      load_config!
    end

    # Merge configuration
    def merge!(hash)
      hash.each do |key, value|
        @data[key.to_sym] = value
      end
    end

    # Convert to hash
    def to_h
      @data.dup
    end

    # Class method to load config
    def self.load(workspace)
      new(workspace: workspace)
    end

    # Global default config
    def self.default
      @default ||= new
    end

    private

    def load_config!
      load_workspace_config if @workspace
      load_global_config
      load_env_overrides
    end

    def load_workspace_config
      config_file = @workspace.join(CONFIG_DIR, CONFIG_FILE)
      return unless config_file.exist?

      data = YAML.safe_load_file(config_file, permitted_classes: [Symbol])
      merge!(data) if data.is_a?(Hash)
    rescue StandardError => e
      Pocketrb.logger.warn("Failed to load workspace config: #{e.message}")
    end

    def load_global_config
      global_config = Pathname.new(Dir.home).join(".pocketrb", CONFIG_FILE)
      return unless global_config.exist?

      data = YAML.safe_load_file(global_config, permitted_classes: [Symbol])
      # Global config has lower priority than workspace config
      data.each { |k, v| @data[k.to_sym] ||= v } if data.is_a?(Hash)
    rescue StandardError => e
      Pocketrb.logger.warn("Failed to load global config: #{e.message}")
    end

    def load_env_overrides
      # Environment variables override config file
      warn_env_deprecated("POCKETRB_PROVIDER", "provider") if ENV["POCKETRB_PROVIDER"]
      @data[:provider] = ENV["POCKETRB_PROVIDER"] if ENV["POCKETRB_PROVIDER"]

      warn_env_deprecated("POCKETRB_MODEL", "model") if ENV["POCKETRB_MODEL"]
      @data[:model] = ENV["POCKETRB_MODEL"] if ENV["POCKETRB_MODEL"]

      if ENV["POCKETRB_MAX_ITERATIONS"]
        warn_env_deprecated("POCKETRB_MAX_ITERATIONS", "max_iterations")
        @data[:max_iterations] = ENV["POCKETRB_MAX_ITERATIONS"].to_i
      end

      warn_env_deprecated("MCP_ENDPOINT", "mcp_endpoint") if ENV["MCP_ENDPOINT"]
      @data[:mcp_endpoint] = ENV["MCP_ENDPOINT"] if ENV["MCP_ENDPOINT"]

      # Autonomous mode (for sandboxed environments)
      if %w[1 true].include?(ENV["POCKETRB_AUTONOMOUS"])
        warn_env_deprecated("POCKETRB_AUTONOMOUS", "autonomous")
        @data[:autonomous] = true
      end

      # Log level
      return unless ENV["POCKETRB_LOG_LEVEL"]

      warn_env_deprecated("POCKETRB_LOG_LEVEL", "log_level")
      @data[:log_level] = ENV.fetch("POCKETRB_LOG_LEVEL", nil)
      Pocketrb.logger.level = Logger.const_get(ENV["POCKETRB_LOG_LEVEL"].upcase)
    end

    # Warn about deprecated environment variable usage
    # @param env_var [String] environment variable name
    # @param config_key [String] recommended config key
    def warn_env_deprecated(env_var, config_key)
      return if @warned_vars&.include?(env_var)

      @warned_vars ||= Set.new
      @warned_vars << env_var

      Pocketrb.logger.warn("[DEPRECATION] ENV['#{env_var}'] is deprecated. " \
                           "Use config.yml: #{config_key} = value")
    end
  end
end
