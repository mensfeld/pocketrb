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
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class ProviderError < Error; end
  class ToolError < Error; end
  class SessionError < Error; end
  class MCPError < Error; end

  class << self
    attr_writer :logger

    def logger
      @logger ||= Logger.new($stdout, level: Logger::INFO)
    end

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
  "qmd" => "QMD",
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
