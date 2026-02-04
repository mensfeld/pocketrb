# frozen_string_literal: true

require "zeitwerk"
require "async"
require "json"
require "yaml"
require "logger"
require "fileutils"
require "pathname"

# Pocketrb: Ruby AI agent with multi-LLM support and advanced planning capabilities
module Pocketrb
  # Base error class for all Pocketrb errors
  class Error < StandardError; end

  # Raised when configuration is invalid or corrupted
  class ConfigurationError < Error; end

  # Raised when LLM provider encounters an error
  class ProviderError < Error; end

  # Raised when tool execution fails
  class ToolError < Error; end

  # Raised when session management encounters an error
  class SessionError < Error; end

  # Raised when MCP (Model Context Protocol) operations fail
  class MCPError < Error; end

  class << self
    attr_writer :logger

    # Returns the logger instance for Pocketrb
    # @return [Logger] the logger instance
    def logger
      @logger ||= Logger.new($stdout, level: Logger::INFO)
    end

    # Returns the root directory of the Pocketrb gem
    # @return [Pathname] the gem root directory
    # @example
    #   Pocketrb.root #=> #<Pathname:/path/to/pocketrb>
    def root
      @root ||= Pathname.new(__dir__).parent
    end
  end
end

# Set up Zeitwerk autoloader
loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  "cli" => "CLI",
  "llm" => "LLM",
  "mcp" => "MCP",
  "openrouter" => "OpenRouter",
  "ruby_llm_provider" => "RubyLLMProvider",
  "claude_cli" => "ClaudeCLI",
  "claude_max_proxy" => "ClaudeMaxProxy",
  "whatsapp" => "WhatsApp"
)

# Tell Zeitwerk to ignore files that don't follow naming conventions
# (they're loaded by their parent module)
loader.ignore("#{__dir__}/pocketrb/bus/events.rb")
loader.ignore("#{__dir__}/pocketrb/providers/types.rb")

loader.setup

# Manually require files that define multiple classes
require_relative "pocketrb/bus/events"
require_relative "pocketrb/providers/types"

# Eager load in production for thread safety
loader.eager_load if ENV["POCKETRB_EAGER_LOAD"]
