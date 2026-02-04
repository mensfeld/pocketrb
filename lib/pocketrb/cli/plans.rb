# frozen_string_literal: true

module Pocketrb
  class CLI
    # Plans command - lists active execution plans
    class Plans < Base
      desc "plans", "List active plans"
      # Lists all active execution plans in the workspace
      # @return [void]
      def call
        workspace = resolve_workspace
        manager = Pocketrb::Planning::Manager.new(workspace: workspace)

        plans = manager.list_plans
        if plans.empty?
          say "No plans found", :yellow
          return
        end

        plans.each do |plan|
          say "\n#{plan.to_markdown}"
        end
      end

      default_task :call
    end
  end
end
