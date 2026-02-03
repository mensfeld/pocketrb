# frozen_string_literal: true

module Pocketrb
  module Tools
    # Registry for managing available tools
    class Registry
      attr_reader :context

      def initialize(context = {})
        @tools = {}
        @context = context
      end

      # Register a tool instance
      # @param tool [Base] Tool instance
      def register(tool)
        raise ArgumentError, "Tool must inherit from Tools::Base" unless tool.is_a?(Base)

        @tools[tool.name] = tool
        Pocketrb.logger.debug("Registered tool: #{tool.name}")
      end

      # Register a tool class (will be instantiated with context)
      # @param klass [Class] Tool class
      def register_class(klass)
        tool = klass.new(@context)
        register(tool)
      end

      # Unregister a tool
      # @param name [String] Tool name
      def unregister(name)
        @tools.delete(name)
      end

      # Get a tool by name
      # @param name [String] Tool name
      # @return [Base|nil]
      def get(name)
        @tools[name]
      end

      # Check if a tool exists
      # @param name [String] Tool name
      # @return [Boolean]
      def exists?(name)
        @tools.key?(name)
      end

      # Get all tool names
      # @return [Array<String>]
      def names
        @tools.keys
      end

      # Get all available tool definitions (for LLM)
      # @param filter_unavailable [Boolean] Exclude unavailable tools
      # @return [Array<Hash>]
      def definitions(filter_unavailable: true)
        tools = filter_unavailable ? available_tools : @tools.values
        tools.map(&:to_definition)
      end

      # Get Anthropic-format definitions
      # @return [Array<Hash>]
      def anthropic_definitions(filter_unavailable: true)
        tools = filter_unavailable ? available_tools : @tools.values
        tools.map(&:to_anthropic_definition)
      end

      # Execute a tool
      # @param name [String] Tool name
      # @param arguments [Hash] Tool arguments
      # @return [String] Result
      def execute(name, arguments)
        tool = get(name)
        raise ToolError, "Unknown tool: #{name}" unless tool
        raise ToolError, "Tool #{name} is not available" unless tool.available?

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          # Convert string keys to symbols
          args = arguments.transform_keys(&:to_sym)
          result = tool.execute(**args)

          duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).to_i
          Pocketrb.logger.debug("Tool #{name} executed in #{duration}ms")

          result
        rescue StandardError => e
          Pocketrb.logger.error("Tool #{name} failed: #{e.message}")
          raise ToolError, "Tool execution failed: #{e.message}"
        end
      end

      # Get only available tools
      # @return [Array<Base>]
      def available_tools
        @tools.values.select(&:available?)
      end

      # Number of registered tools
      # @return [Integer]
      def size
        @tools.size
      end

      # Clear all tools
      def clear!
        @tools.clear
      end

      # Update context for all tools
      def update_context(new_context)
        @context = @context.merge(new_context)
        @tools.each_value { |tool| tool.instance_variable_set(:@context, @context) }
      end

      # Register default core tools
      def register_defaults!
        [
          ReadFile,
          WriteFile,
          EditFile,
          ListDir,
          Exec,
          Jobs,
          WebSearch,
          WebFetch,
          Think,
          Message
        ].each { |klass| register_class(klass) }
      end
    end
  end
end
