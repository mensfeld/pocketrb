# frozen_string_literal: true

module Pocketrb
  class CLI
    # Skills command - lists available skills from workspace
    class Skills < Base
      desc "skills", "List available skills"
      # Lists all available skills from the workspace skills directory
      # @return [void]
      def call
        workspace = resolve_workspace
        loader = Pocketrb::Skills::Loader.new(workspace: workspace)

        skills = loader.list_skills
        if skills.empty?
          say "No skills found in #{workspace}/skills/", :yellow
          return
        end

        say "Available skills:"
        skills.each do |skill|
          flags = []
          flags << "always" if skill.always?
          flags << "triggers: #{skill.triggers.join(", ")}" if skill.triggers.any?

          flag_str = flags.any? ? " (#{flags.join(", ")})" : ""
          say "  - #{skill.name}: #{skill.description}#{flag_str}"
        end
      end

      default_task :call
    end
  end
end
