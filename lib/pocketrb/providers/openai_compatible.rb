# frozen_string_literal: true

require "uri"

module Pocketrb
  module Providers
    # Provider for any server exposing the OpenAI chat completions API (vLLM, llama.cpp server,
    # llamafile, LM Studio, Ollama, OpenAI itself)
    class OpenAICompatible < OpenRouter
      # Provider name
      # @return [Symbol]
      def name
        :openai_compatible
      end

      # Default model, taken from the configuration
      # @return [String, nil]
      def default_model
        @config[:model]
      end

      # Available models
      # @return [Array<String>]
      def available_models
        [default_model].compact
      end

      protected

      # Validate that an http(s) base URL is configured
      # @return [void]
      # @raise [ConfigurationError] if base URL is missing or invalid
      def validate_config!
        if base_url.to_s.empty?
          raise ConfigurationError, "openai_compatible_base_url is required for #{self.class.name}"
        end

        return if http_url?(base_url)

        raise ConfigurationError, "openai_compatible_base_url must be an http(s) URL, got #{base_url.inspect}"
      end

      private

      # Base URL of the API, e.g. http://localhost:8000/v1
      # @return [String, nil]
      def base_url
        @config[:openai_compatible_base_url] || ENV.fetch("OPENAI_COMPATIBLE_BASE_URL", nil)
      end

      # Check that a value is an http(s) URL with a host
      # @param value [String] URL to check
      # @return [Boolean]
      def http_url?(value)
        uri = URI.parse(value)
        uri.is_a?(URI::HTTP) && !uri.host.to_s.empty?
      rescue URI::InvalidURIError
        false
      end

      # Provider label used in error messages
      # @return [String]
      def api_label
        "OpenAI-compatible"
      end

      # Build Faraday HTTP client, sending the API key only when one is configured
      # @return [Faraday::Connection]
      def client
        @client ||= Faraday.new(url: base_url) do |f|
          f.headers["Content-Type"] = "application/json"
          key = api_key(:openai_compatible_api_key)
          f.headers["Authorization"] = "Bearer #{key}" if key
          f.adapter Faraday.default_adapter
        end
      end
    end
  end
end
