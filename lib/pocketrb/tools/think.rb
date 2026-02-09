# frozen_string_literal: true

module Pocketrb
  module Tools
    # Internal reasoning tool for complex problem solving
    class Think < Base
      # Tool name
      # @return [String]
      def name
        "think"
      end

      # Tool description
      # @return [String]
      def description
        "Use this tool to think through complex problems step by step. The content is not shown to the user but helps you reason through the task. Use it when you need to analyze information, plan an approach, or work through logic."
      end

      # Parameter schema
      # @return [Hash]
      def parameters
        {
          type: "object",
          properties: {
            thought: {
              type: "string",
              description: "Your internal reasoning or analysis"
            }
          },
          required: ["thought"]
        }
      end

      # Execute thinking process
      # @param thought [String] Internal reasoning or analysis text
      # @return [String] Confirmation message
      def execute(thought:)
        # The thought is logged but not displayed to the user
        Pocketrb.logger.debug("Agent thought: #{thought[0..200]}...")
        "Thought recorded."
      end
    end
  end
end
