# frozen_string_literal: true

module Pocketrb
  module Providers
    # Registry for LLM providers
    class Registry
      class << self
        # Get registry singleton instance
        # @return [Registry] Registry instance
        def instance
          @instance ||= new
        end

        # Register a provider (class method)
        # @param name [String, Symbol] Provider name
        # @param klass [Class] Provider class
        # @return [void]
        def register(name, klass)
          instance.register(name, klass)
        end

        # Get a provider instance (class method)
        # @param name [String, Symbol] Provider name
        # @param config [Hash] Provider configuration (defaults to empty hash)
        # @return [Base] Provider instance
        def get(name, config = {})
          instance.get(name, config)
        end

        # Get list of available provider names (class method)
        # @return [Array<Symbol>] Provider names
        def available
          instance.available
        end
      end

      def initialize
        @providers = {}
        register_defaults
      end

      # Register a provider class
      # @param name [String, Symbol] Provider name
      # @param klass [Class] Provider class
      # @return [void]
      def register(name, klass)
        @providers[name.to_sym] = klass
      end

      # Get an instance of a provider
      # @param name [String, Symbol] Provider name
      # @param config [Hash] Provider configuration (defaults to empty hash)
      # @return [Base] Provider instance
      # @raise [ConfigurationError] if provider is not registered
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
        register(:claude_max_proxy, ClaudeMaxProxy)
      end
    end
  end
end
