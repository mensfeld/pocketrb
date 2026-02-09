# frozen_string_literal: true

module Pocketrb
  class CLI
    # Config command - manages configuration
    class Config < Thor
      desc "show", "Show current configuration"
      # Display current configuration values
      def show
        workspace = options[:workspace] || Dir.pwd
        config = Pocketrb::Config.load(workspace)

        say "Configuration for #{workspace}:"
        config.to_h.each do |key, value|
          # Don't show API keys
          display_value = key.to_s.include?("api_key") ? "[REDACTED]" : value
          say "  #{key}: #{display_value}"
        end
      end

      desc "set KEY VALUE", "Set a configuration value"
      # @param key [String] Configuration key to set
      # @param value [String] Value to assign (will be auto-converted to int, float, or boolean if applicable)
      def set(key, value)
        workspace = options[:workspace] || Dir.pwd
        config = Pocketrb::Config.load(workspace)

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
      # @param key [String] Configuration key to retrieve
      def get(key)
        workspace = options[:workspace] || Dir.pwd
        config = Pocketrb::Config.load(workspace)

        value = config[key]
        if value
          say "#{key}: #{value}"
        else
          say "Key '#{key}' not found", :yellow
        end
      end
    end
  end
end
