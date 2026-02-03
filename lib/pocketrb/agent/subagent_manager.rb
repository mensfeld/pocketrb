# frozen_string_literal: true

require "securerandom"

module Pocketrb
  module Agent
    # Manages spawning and coordinating subagents
    class SubagentManager
      attr_reader :active_agents

      def initialize(parent_loop:)
        @parent_loop = parent_loop
        @active_agents = {}
        @mutex = Mutex.new
      end

      # Spawn a new subagent for a specific task
      # @param task [String] Task description
      # @param skills [Array<String>] Skills to load for this agent
      # @param origin_channel [Symbol] Channel to report back to
      # @param origin_chat_id [String] Chat to report back to
      # @param model [String] Model to use (defaults to parent's model)
      # @return [String] Agent ID
      def spawn(task:, skills: [], origin_channel:, origin_chat_id:, model: nil)
        agent_id = SecureRandom.uuid[0..7]

        agent_info = {
          id: agent_id,
          task: task,
          skills: skills,
          origin_channel: origin_channel,
          origin_chat_id: origin_chat_id,
          model: model || @parent_loop.model,
          status: :starting,
          started_at: Time.now,
          result: nil
        }

        @mutex.synchronize do
          @active_agents[agent_id] = agent_info
        end

        # Run agent in async task
        Async do
          run_agent(agent_id, agent_info)
        end

        Pocketrb.logger.info("Spawned subagent #{agent_id} for task: #{task[0..50]}...")
        agent_id
      end

      # Get status of a subagent
      # @param agent_id [String]
      # @return [Hash|nil]
      def get_status(agent_id)
        @mutex.synchronize { @active_agents[agent_id]&.dup }
      end

      # List all active agents
      # @return [Array<Hash>]
      def list_active
        @mutex.synchronize do
          @active_agents.values.select { |a| a[:status] == :running }
        end
      end

      # Terminate a subagent
      # @param agent_id [String]
      def terminate(agent_id)
        @mutex.synchronize do
          if @active_agents[agent_id]
            @active_agents[agent_id][:status] = :terminated
          end
        end
      end

      # Wait for a subagent to complete
      # @param agent_id [String]
      # @param timeout [Integer] Timeout in seconds
      # @return [String|nil] Result
      def wait_for(agent_id, timeout: 300)
        deadline = Time.now + timeout

        loop do
          status = get_status(agent_id)
          return nil unless status

          case status[:status]
          when :completed
            return status[:result]
          when :failed, :terminated
            return nil
          end

          break if Time.now > deadline

          sleep 0.5
        end

        nil
      end

      private

      def run_agent(agent_id, info)
        update_status(agent_id, :running)

        # Create isolated context for subagent
        system_prompt = build_subagent_prompt(info)

        # Create a mini message bus for this agent
        sub_bus = Bus::MessageBus.new

        # Create the subagent loop
        sub_loop = Loop.new(
          bus: sub_bus,
          provider: @parent_loop.provider,
          workspace: @parent_loop.workspace,
          model: info[:model],
          max_iterations: 30,
          system_prompt: system_prompt
        )

        # Load requested skills
        load_skills(sub_loop, info[:skills])

        # Process the task
        msg = Bus::InboundMessage.new(
          channel: :subagent,
          sender_id: "parent",
          chat_id: agent_id,
          content: info[:task]
        )

        response = sub_loop.process_message(msg)

        # Report result
        result = response&.content || "Task completed with no output"
        update_status(agent_id, :completed, result: result)

        # Send result back to origin
        announce_result(info, result)

      rescue StandardError => e
        Pocketrb.logger.error("Subagent #{agent_id} failed: #{e.message}")
        update_status(agent_id, :failed, result: "Error: #{e.message}")
        announce_result(info, "Subagent failed: #{e.message}")
      end

      def update_status(agent_id, status, result: nil)
        @mutex.synchronize do
          if @active_agents[agent_id]
            @active_agents[agent_id][:status] = status
            @active_agents[agent_id][:result] = result if result
            @active_agents[agent_id][:completed_at] = Time.now if %i[completed failed terminated].include?(status)
          end
        end
      end

      def build_subagent_prompt(info)
        <<~PROMPT
          You are a specialized subagent spawned to complete a specific task.
          You should focus exclusively on the task and report your findings concisely.

          Your task: #{info[:task]}

          Guidelines:
          - Focus only on the assigned task
          - Be concise in your response
          - If you need information you don't have, say so
          - Complete the task as efficiently as possible
        PROMPT
      end

      def load_skills(loop, skill_names)
        return if skill_names.empty?

        skills_loader = Skills::Loader.new(workspace: @parent_loop.workspace)
        skill_content = skill_names.map do |name|
          skill = skills_loader.load_skill(name)
          skill&.to_prompt
        end.compact.join("\n\n")

        loop.context.append_to_system_prompt(skill_content) unless skill_content.empty?
      end

      def announce_result(info, result)
        outbound = Bus::OutboundMessage.new(
          channel: info[:origin_channel],
          chat_id: info[:origin_chat_id],
          content: "**Subagent completed:**\n\n#{result}",
          metadata: { subagent_id: info[:id] }
        )

        @parent_loop.bus.publish_outbound(outbound)
      end
    end
  end
end
