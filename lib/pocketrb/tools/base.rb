# frozen_string_literal: true

module Pocketrb
  module Tools
    # Base class for all tools
    class Base
      attr_reader :context

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
      # @param kwargs [Hash] Tool arguments
      # @return [String] Result
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
      def success(message)
        message.to_s
      end

      # Helper to build an error result
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
      def resolve_path(path)
        return Pathname.new(path) if Pathname.new(path).absolute?

        workspace ? workspace.join(path) : Pathname.new(path)
      end

      # Check if path is within workspace (security)
      def path_allowed?(path)
        return true unless workspace

        resolved = resolve_path(path).expand_path
        workspace_expanded = workspace.expand_path

        resolved.to_s.start_with?(workspace_expanded.to_s)
      end

      # Validate path is allowed and exists
      def validate_path!(path, must_exist: true)
        resolved = resolve_path(path)

        unless path_allowed?(path)
          raise ToolError, "Path #{path} is outside workspace"
        end

        if must_exist && !resolved.exist?
          raise ToolError, "Path does not exist: #{path}"
        end

        resolved
      end
    end
  end
end
