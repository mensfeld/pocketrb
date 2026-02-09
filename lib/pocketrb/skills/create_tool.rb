# frozen_string_literal: true

module Pocketrb
  # Skills system for reusable prompts and capabilities
  module Skills
    # Tool for creating new skills at runtime
    class CreateTool < Tools::Base
      # Tool name
      # @return [String] Tool identifier
      def name
        "skill_create"
      end

      # Tool description
      # @return [String] Human-readable description
      def description
        "Create a new skill. Skills are reusable prompts/instructions that can be loaded into context. Use this to teach yourself new capabilities."
      end

      # Tool parameters schema
      # @return [Hash] JSON schema for tool parameters
      def parameters
        {
          type: "object",
          properties: {
            skill_name: {
              type: "string",
              description: "Name of the skill (lowercase, hyphens allowed, e.g., 'code-review')"
            },
            skill_description: {
              type: "string",
              description: "Brief description of what the skill does"
            },
            content: {
              type: "string",
              description: "The skill content - instructions, prompts, or guidelines"
            },
            triggers: {
              type: "array",
              items: { type: "string" },
              description: "Keywords that automatically trigger this skill"
            },
            always: {
              type: "boolean",
              description: "Whether this skill should always be loaded (default: false)"
            }
          },
          required: %w[skill_name skill_description content]
        }
      end

      # Execute skill creation
      # @param skill_name [String] Skill name (lowercase, hyphens allowed)
      # @param skill_description [String] Brief skill description
      # @param content [String] Skill content/instructions in markdown
      # @param triggers [Array<String>, nil] Keywords that trigger this skill
      # @param always [Boolean] Whether skill should always be loaded (defaults to false)
      # @return [String] Success or error message
      def execute(skill_name:, skill_description:, content:, triggers: nil, always: false)
        # Validate skill name
        unless valid_skill_name?(skill_name)
          return error("Invalid skill name. Use lowercase letters, numbers, and hyphens only.")
        end

        # Create skill directory
        skill_dir = workspace.join("skills", skill_name)

        return error("Skill '#{skill_name}' already exists. Use skill_modify to update it.") if skill_dir.exist?

        FileUtils.mkdir_p(skill_dir)

        # Build skill content with frontmatter
        skill_content = build_skill_file(skill_name, skill_description, content, triggers, always)

        # Write SKILL.md
        skill_file = skill_dir.join("SKILL.md")
        File.write(skill_file, skill_content)

        # Update TOOLS.md if it exists
        update_tools_documentation(skill_name, skill_description)

        success("Created skill '#{skill_name}' at #{skill_file}")
      end

      private

      def valid_skill_name?(name)
        name.match?(/\A[a-z][a-z0-9-]*\z/)
      end

      def build_skill_file(name, description, content, triggers, always)
        metadata = {
          "name" => name,
          "description" => description
        }
        metadata["triggers"] = triggers if triggers && !triggers.empty?
        metadata["always"] = true if always

        <<~MD
          ---
          #{metadata.to_yaml.lines[1..].join}---

          #{content}
        MD
      end

      def update_tools_documentation(skill_name, description)
        tools_file = workspace.join("TOOLS.md")
        return unless tools_file.exist?

        content = File.read(tools_file)

        # Find skills section and add new skill
        if content.include?("## Skills")
          # Add to existing skills section
          skills_section_end = content.index(/\n##[^#]/, content.index("## Skills") + 1) || content.length
          insert_point = skills_section_end

          new_entry = "\n- **#{skill_name}**: #{description}"

          new_content = content[0...insert_point] + new_entry + content[insert_point..]
          File.write(tools_file, new_content)
        end
      rescue StandardError => e
        Pocketrb.logger.warn("Failed to update TOOLS.md: #{e.message}")
      end
    end
  end
end
