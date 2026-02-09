# frozen_string_literal: true

module Pocketrb
  module Planning
    # Tool for creating and managing execution plans
    class Tool < Tools::Base
      # Tool name
      # @return [String] Tool identifier
      def name
        "plan"
      end

      # Tool description
      # @return [String] Human-readable description
      def description
        "Create and manage execution plans for complex tasks. Plans help organize multi-step work and track progress."
      end

      # Tool parameters schema
      # @return [Hash] JSON schema
      def parameters
        {
          type: "object",
          properties: {
            action: {
              type: "string",
              enum: %w[create update complete fail list show delete],
              description: "Action to perform"
            },
            plan_name: {
              type: "string",
              description: "Name of the plan"
            },
            plan_description: {
              type: "string",
              description: "Description of the plan (for create)"
            },
            steps: {
              type: "array",
              items: { type: "string" },
              description: "Steps to add (for create or update)"
            },
            step_index: {
              type: "integer",
              description: "Step index to update (0-indexed)"
            },
            notes: {
              type: "string",
              description: "Notes for the step completion/failure"
            }
          },
          required: ["action"]
        }
      end

      # Execute planning operation
      # @param action [String] Action to perform (create, update, complete, fail, list, show)
      # @param plan_name [String, nil] Plan name
      # @param plan_description [String, nil] Plan description (for create action)
      # @param steps [Array<String>, nil] Step descriptions (for create/update actions)
      # @param step_index [Integer, nil] Step index (for complete/fail actions)
      # @param notes [String, nil] Notes for step completion/failure
      # @return [String] JSON result of operation
      def execute(
        action:,
        plan_name: nil,
        plan_description: nil,
        steps: nil,
        step_index: nil,
        notes: nil
      )
        case action
        when "create"
          create_plan(plan_name, plan_description, steps)
        when "update"
          update_plan(plan_name, steps, step_index, notes)
        when "complete"
          complete_step(plan_name, step_index, notes)
        when "fail"
          fail_step(plan_name, step_index, notes)
        when "list"
          list_plans
        when "show"
          show_plan(plan_name)
        when "delete"
          delete_plan(plan_name)
        else
          error("Unknown action: #{action}")
        end
      end

      private

      def manager
        @manager ||= Manager.new(workspace: workspace)
      end

      def create_plan(name, description, steps)
        return error("Plan name is required") unless name
        return error("At least one step is required") if steps.nil? || steps.empty?

        plan = manager.create_plan(name: name, description: description, steps: steps)
        plan.activate!
        manager.update_plan(name: name) # Save activated state

        success("Created and activated plan '#{name}' with #{steps.length} steps\n\n#{plan.to_markdown}")
      rescue Error => e
        error(e.message)
      end

      def update_plan(name, new_steps, step_index, notes)
        return error("Plan name is required") unless name

        plan = manager.update_plan(
          name: name,
          completed_step: step_index,
          new_steps: new_steps,
          notes: notes
        )

        success("Updated plan '#{name}'\n\n#{plan.to_markdown}")
      rescue Error => e
        error(e.message)
      end

      def complete_step(name, step_index, notes)
        return error("Plan name is required") unless name
        return error("Step index is required") if step_index.nil?

        plan = manager.update_plan(name: name, completed_step: step_index, notes: notes)

        if plan.complete?
          success("Completed step #{step_index + 1}. Plan '#{name}' is now complete!\n\n#{plan.to_markdown}")
        else
          next_step = plan.next_step
          success("Completed step #{step_index + 1}. Next: Step #{next_step.index + 1} - #{next_step.description}\n\n#{plan.to_markdown}")
        end
      rescue Error => e
        error(e.message)
      end

      def fail_step(name, step_index, notes)
        return error("Plan name is required") unless name
        return error("Step index is required") if step_index.nil?

        plan = manager.fail_step(name: name, step_index: step_index, notes: notes)
        success("Marked step #{step_index + 1} as failed\n\n#{plan.to_markdown}")
      rescue Error => e
        error(e.message)
      end

      def list_plans
        plans = manager.list_plans

        return "No plans found" if plans.empty?

        output = ["# Plans\n"]
        plans.each do |plan|
          status_emoji = case plan.status
                         when Plan::PlanStatus::ACTIVE then "🔄"
                         when Plan::PlanStatus::COMPLETED then "✅"
                         when Plan::PlanStatus::FAILED then "❌"
                         when Plan::PlanStatus::CANCELLED then "🚫"
                         else "📝"
                         end

          output << "#{status_emoji} **#{plan.name}** - #{plan.progress}% (#{plan.status})"
        end

        output.join("\n")
      end

      def show_plan(name)
        return error("Plan name is required") unless name

        plan = manager.get_plan(name)
        return error("Plan '#{name}' not found") unless plan

        plan.to_markdown
      end

      def delete_plan(name)
        return error("Plan name is required") unless name

        manager.delete_plan(name)
        success("Deleted plan '#{name}'")
      end
    end
  end
end
