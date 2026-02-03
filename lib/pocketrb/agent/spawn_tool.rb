# frozen_string_literal: true

module Pocketrb
  module Agent
    # Tool for spawning subagents
    class SpawnTool < Tools::Base
      def name
        "spawn"
      end

      def description
        "Spawn a subagent to work on a specific task in the background. Useful for delegating independent work or parallel processing."
      end

      def parameters
        {
          type: "object",
          properties: {
            task: {
              type: "string",
              description: "The task for the subagent to complete"
            },
            skills: {
              type: "array",
              items: { type: "string" },
              description: "Skills to load for this subagent"
            },
            wait: {
              type: "boolean",
              description: "Wait for the subagent to complete before returning (default: false)"
            },
            timeout: {
              type: "integer",
              description: "Timeout in seconds if waiting (default: 300)"
            }
          },
          required: ["task"]
        }
      end

      def available?
        @context[:subagent_manager] != nil
      end

      def execute(task:, skills: [], wait: false, timeout: 300)
        manager = @context[:subagent_manager]
        return error("Subagent spawning not available") unless manager

        origin_channel = @context[:current_channel] || :cli
        origin_chat_id = @context[:current_chat_id] || "main"

        agent_id = manager.spawn(
          task: task,
          skills: skills,
          origin_channel: origin_channel,
          origin_chat_id: origin_chat_id
        )

        if wait
          result = manager.wait_for(agent_id, timeout: timeout)
          if result
            success("Subagent #{agent_id} completed:\n\n#{result}")
          else
            error("Subagent #{agent_id} did not complete within timeout")
          end
        else
          success("Spawned subagent #{agent_id} for task: #{task[0..100]}...\nResults will be announced when complete.")
        end
      end
    end
  end
end
