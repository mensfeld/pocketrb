# frozen_string_literal: true

module Pocketrb
  module Agent
    # Builds context for LLM requests
    class Context
      TOOL_GUIDELINES = <<~PROMPT
        ## Tool Usage Guidelines

        You have access to tools for interacting with files, executing commands, and searching the web.

        - Use tools when they would help accomplish the user's request
        - Be concise and direct in your responses
        - When executing commands, explain what you're doing
        - If a task requires multiple steps, plan them out first
        - Report errors clearly and suggest fixes when possible
        - Use the memory tool to store important information for future reference
        - Search memory when the user asks about something you may have learned before
      PROMPT

      DEFAULT_IDENTITY = <<~PROMPT
        You are Pocketrb, an AI assistant with access to tools for interacting with files, executing commands, and searching the web.
      PROMPT

      attr_reader :system_prompt, :workspace, :skills_summary, :qmd_memory

      def initialize(workspace: nil, system_prompt: nil, skills_summary: nil, qmd_memory: nil)
        @workspace = workspace
        @skills_summary = skills_summary
        @qmd_memory = qmd_memory
        @system_prompt = system_prompt || build_base_prompt
      end

      private

      def build_base_prompt
        parts = []

        # Load identity from file or use default
        identity = load_workspace_file("IDENTITY.md")
        parts << (identity || DEFAULT_IDENTITY)

        # Add tool guidelines
        parts << TOOL_GUIDELINES

        # Load static memory/knowledge if exists
        memory = load_workspace_file("MEMORY.md")
        parts << "## Background Knowledge\n\n#{memory}" if memory

        parts.join("\n\n")
      end

      def load_workspace_file(filename)
        return nil unless @workspace

        path = @workspace.join(filename)
        return nil unless path.exist?

        content = File.read(path).strip
        content.empty? ? nil : content
      rescue StandardError => e
        Pocketrb.logger.debug("Failed to load #{filename}: #{e.message}")
        nil
      end

      public

      # Build the complete message array for an LLM request
      # @param history [Array<Message>] Conversation history
      # @param current [String] Current user message
      # @param media [Array<Bus::Media>] Media attachments
      # @param memory_context [String|nil] Memory/context from QMD (optional override)
      # @return [Array<Message>]
      def build_messages(history:, current:, media: nil, memory_context: nil)
        messages = []

        # Add system message with memory context based on current message
        messages << build_system_message(memory_context, current_message: current)

        # Add conversation history
        messages.concat(history)

        # Add current user message with media
        messages << Providers::Message.user(current, media: media)

        messages
      end

      # Build messages for continuing after tool execution
      # @param history [Array<Message>] Full history including tool results
      # @return [Array<Message>]
      def build_continuation(history:, memory_context: nil)
        messages = []
        messages << build_system_message(memory_context)
        messages.concat(history)
        messages
      end

      # Update system prompt
      def update_system_prompt(prompt)
        @system_prompt = prompt
      end

      # Add to system prompt
      def append_to_system_prompt(content)
        @system_prompt = "#{@system_prompt}\n\n#{content}"
      end

      # Update skills summary
      def update_skills_summary(summary)
        @skills_summary = summary
      end

      # Get relevant memory context for a message
      # @param message [String] The user message
      # @return [String] Memory context
      def get_memory_context(message)
        return nil unless @qmd_memory

        @qmd_memory.relevant_context(message)
      rescue StandardError => e
        Pocketrb.logger.debug("Failed to get memory context: #{e.message}")
        nil
      end

      private

      def build_system_message(memory_context = nil, current_message: nil)
        parts = [@system_prompt]

        # Add workspace info
        parts << "Working directory: #{@workspace}" if @workspace

        # Add skills summary
        parts << "Available skills:\n#{@skills_summary}" if @skills_summary && !@skills_summary.empty?

        # Add memory context (passed directly or fetched from QMD)
        if memory_context && !memory_context.empty?
          parts << "Relevant context from memory:\n#{memory_context}"
        elsif @qmd_memory && current_message
          # Fetch relevant context from QMD memory based on current message
          qmd_context = get_memory_context(current_message)
          parts << "Relevant context from memory:\n#{qmd_context}" if qmd_context && !qmd_context.empty?
        end

        # Add timestamp
        parts << "Current time: #{Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")}"

        Providers::Message.system(parts.join("\n\n"))
      end
    end
  end
end
