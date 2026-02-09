# frozen_string_literal: true

require "json"

module Pocketrb
  # Planning system with step-by-step execution plans
  module Planning
    # Manages plans persistence and lifecycle
    class Manager
      attr_reader :workspace

      # Initialize planning manager
      # @param workspace [String, Pathname] Workspace directory path for storing plans
      def initialize(workspace:)
        @workspace = Pathname.new(workspace)
        @plans_dir = @workspace.join(".pocketrb", "plans")
        @plans_cache = {}

        ensure_plans_dir!
      end

      # Create a new plan
      # @param name [String] Plan name
      # @param steps [Array<String>] Step descriptions
      # @param description [String] Plan description
      # @return [Plan]
      def create_plan(name:, steps:, description: nil)
        raise Error, "Plan '#{name}' already exists" if exists?(name)

        plan = Plan.new(name: name, description: description)
        plan.add_steps(steps)

        save_plan(plan)
        @plans_cache[name] = plan

        Pocketrb.logger.info("Created plan: #{name} with #{steps.length} steps")
        plan
      end

      # Get a plan by name
      # @param name [String] Plan name
      # @return [Plan, nil]
      def get_plan(name)
        @plans_cache[name] ||= load_plan(name)
      end

      # Update a plan
      # @param name [String] Plan name
      # @param completed_step [Integer] Step index to mark complete
      # @param new_steps [Array<String>] Steps to add
      # @param notes [String] Notes for completed step
      def update_plan(name:, completed_step: nil, new_steps: nil, notes: nil)
        plan = get_plan(name)
        raise Error, "Plan '#{name}' not found" unless plan

        plan.complete_step(completed_step, notes: notes) if completed_step

        plan.add_steps(new_steps) if new_steps

        # Auto-complete plan if all steps done
        plan.mark_complete! if plan.complete? && plan.status == Plan::PlanStatus::ACTIVE

        save_plan(plan)
        plan
      end

      # Fail a step in a plan
      # @param name [String] Plan name
      # @param step_index [Integer] Index of step to mark as failed
      # @param notes [String, nil] Optional failure notes
      # @return [Plan] Updated plan
      def fail_step(name:, step_index:, notes: nil)
        plan = get_plan(name)
        raise Error, "Plan '#{name}' not found" unless plan

        plan.fail_step(step_index, notes: notes)
        save_plan(plan)
        plan
      end

      # Activate a plan
      # @param name [String] Plan name to activate
      # @return [Plan] Activated plan
      def activate_plan(name)
        plan = get_plan(name)
        raise Error, "Plan '#{name}' not found" unless plan

        plan.activate!
        save_plan(plan)
        plan
      end

      # Mark a plan as complete
      # @param name [String] Plan name to mark complete
      # @return [Plan] Completed plan
      def mark_complete(name)
        plan = get_plan(name)
        raise Error, "Plan '#{name}' not found" unless plan

        plan.mark_complete!
        save_plan(plan)
        plan
      end

      # Cancel a plan
      # @param name [String] Plan name to cancel
      # @return [Plan] Cancelled plan
      def cancel_plan(name)
        plan = get_plan(name)
        raise Error, "Plan '#{name}' not found" unless plan

        plan.cancel!
        save_plan(plan)
        plan
      end

      # Delete a plan
      # @param name [String] Plan name to delete
      # @return [void]
      def delete_plan(name)
        file = plan_file(name)
        File.delete(file) if file.exist?
        @plans_cache.delete(name)
      end

      # Get all active plans
      # @return [Array<Plan>]
      def get_active_plans
        list_plans.select { |p| p.status == Plan::PlanStatus::ACTIVE }
      end

      # Get all plans
      # @return [Array<Plan>]
      def list_plans
        Dir.glob(@plans_dir.join("*.json")).filter_map do |file|
          name = File.basename(file, ".json")
          get_plan(name)
        end
      end

      # Check if a plan exists
      # @param name [String] Plan name to check
      # @return [Boolean] true if plan exists
      def exists?(name)
        plan_file(name).exist?
      end

      private

      def ensure_plans_dir!
        FileUtils.mkdir_p(@plans_dir) unless @plans_dir.exist?
      end

      def plan_file(name)
        safe_name = name.gsub(/[^a-zA-Z0-9_-]/, "_")
        @plans_dir.join("#{safe_name}.json")
      end

      def save_plan(plan)
        file = plan_file(plan.name)
        File.write(file, JSON.pretty_generate(plan.to_h))
      end

      def load_plan(name)
        file = plan_file(name)
        return nil unless file.exist?

        data = JSON.parse(File.read(file))
        Plan.from_h(data)
      rescue JSON::ParserError => e
        Pocketrb.logger.error("Failed to parse plan #{name}: #{e.message}")
        nil
      end
    end
  end
end
