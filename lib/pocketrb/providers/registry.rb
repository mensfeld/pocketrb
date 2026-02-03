# frozen_string_literal: true

module Pocketrb
  module Providers
    # Registry for LLM providers
    class Registry
      class << self
        def instance
          @instance ||= new
        end

        def register(name, klass)
          instance.register(name, klass)
        end

        def get(name, config = {})
          instance.get(name, config)
        end

        def available
          instance.available
        end
      end

      def initialize
        @providers = {}
        register_defaults
      end

      # Register a provider class
      def register(name, klass)
        @providers[name.to_sym] = klass
      end

      # Get an instance of a provider
      def get(name, config = {})
        klass = @providers[name.to_sym]
        raise ConfigurationError, "Unknown provider: #{name}" unless klass

        klass.new(config)
      end

      # List available provider names
      def available
        @providers.keys
      end

      private

      def register_defaults
        register(:anthropic, Anthropic)
        register(:openrouter, OpenRouter)
        register(:ruby_llm, RubyLLMProvider)
        register(:claude_cli, ClaudeCLI)
      end
    end
  end
end
