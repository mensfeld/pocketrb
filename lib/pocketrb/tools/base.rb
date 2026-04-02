# frozen_string_literal: true

module Pocketrb
  module Tools
    # Base class for all tools
    class Base
      attr_reader :context

      # Initialize tool instance
      # @param context [Hash] Shared context hash containing workspace, bus, and other runtime dependencies
      def initialize(context = {})
        @context = context
      end

      # Tool name (must be unique)
      # @return [String]
      def name
        raise NotImplementedError, "#{self.class}#name must be implemented"
      end

      # Human-readable description
      # @return [String]
      def description
        raise NotImplementedError, "#{self.class}#description must be implemented"
      end

      # JSON Schema for parameters
      # @return [Hash]
      def parameters
        { type: "object", properties: {}, required: [] }
      end

      # Execute the tool
      # @option kwargs [Object] * Tool-specific arguments as defined in the parameters schema
      # @return [String] Result
      # @note Subclasses should override this method and define specific parameters matching their schema
      def execute(**kwargs)
        raise NotImplementedError, "#{self.class}#execute must be implemented"
      end

      # Check if tool is available in current context
      # @return [Boolean]
      def available?
        true
      end

      # Convert to OpenAI/Anthropic tool definition format
      # @return [Hash]
      def to_definition
        {
          type: "function",
          function: {
            name: name,
            description: description,
            parameters: parameters
          }
        }
      end

      # Convert to Anthropic-native tool format
      # @return [Hash]
      def to_anthropic_definition
        {
          name: name,
          description: description,
          input_schema: parameters
        }
      end

      protected

      # Helper to build a successful result
      # @param message [Object] content to convert to string
      # @return [String]
      def success(message)
        message.to_s
      end

      # Helper to build an error result
      # @param message [String] error description
      # @return [String]
      def error(message)
        "Error: #{message}"
      end

      # Access workspace from context
      def workspace
        @context[:workspace]
      end

      # Access bus from context
      def bus
        @context[:bus]
      end

      # Resolve a path relative to workspace
      # @param path [String] file or directory path
      # @return [Pathname]
      def resolve_path(path)
        return Pathname.new(path) if Pathname.new(path).absolute?

        workspace ? workspace.join(path) : Pathname.new(path)
      end

      # Check if path is within workspace (security)
      # @param path [String] file or directory path to check
      # @return [Boolean]
      def path_allowed?(path)
        return true unless workspace

        resolved = resolve_path(path).expand_path
        workspace_expanded = workspace.expand_path

        resolved.to_s.start_with?(workspace_expanded.to_s)
      end

      # Validate path is allowed and exists
      # @param path [String] file or directory path to validate
      # @param must_exist [Boolean] whether the path must already exist
      # @return [Pathname] resolved path
      # @raise [ToolError] if path is outside workspace or does not exist
      def validate_path!(path, must_exist: true)
        resolved = resolve_path(path)

        raise ToolError, "Path #{path} is outside workspace" unless path_allowed?(path)

        raise ToolError, "Path does not exist: #{path}" if must_exist && !resolved.exist?

        resolved
      end
    end
  end
end
