# frozen_string_literal: true

module Pocketrb
  module Skills
    # Tool for modifying existing skills
    class ModifyTool < Tools::Base
      def name
        "skill_modify"
      end

      def description
        "Modify an existing skill. Can update the content, description, triggers, or other properties."
      end

      def parameters
        {
          type: "object",
          properties: {
            skill_name: {
              type: "string",
              description: "Name of the skill to modify"
            },
            new_content: {
              type: "string",
              description: "New content for the skill (replaces existing)"
            },
            append_content: {
              type: "string",
              description: "Content to append to the skill"
            },
            new_description: {
              type: "string",
              description: "New description for the skill"
            },
            add_triggers: {
              type: "array",
              items: { type: "string" },
              description: "Triggers to add"
            },
            remove_triggers: {
              type: "array",
              items: { type: "string" },
              description: "Triggers to remove"
            },
            set_always: {
              type: "boolean",
              description: "Set whether skill is always loaded"
            }
          },
          required: ["skill_name"]
        }
      end

      def execute(
        skill_name:,
        new_content: nil,
        append_content: nil,
        new_description: nil,
        add_triggers: nil,
        remove_triggers: nil,
        set_always: nil
      )
        skill_file = workspace.join("skills", skill_name, "SKILL.md")

        return error("Skill '#{skill_name}' not found") unless skill_file.exist?

        # Parse existing skill
        content = File.read(skill_file)
        metadata, body = parse_frontmatter(content)

        # Apply modifications
        metadata["description"] = new_description if new_description

        if add_triggers
          metadata["triggers"] ||= []
          metadata["triggers"] = (metadata["triggers"] + add_triggers).uniq
        end

        if remove_triggers
          metadata["triggers"] ||= []
          metadata["triggers"] -= remove_triggers
          metadata.delete("triggers") if metadata["triggers"].empty?
        end

        metadata["always"] = set_always unless set_always.nil?

        if new_content
          body = new_content
        elsif append_content
          body = "#{body}\n\n#{append_content}"
        end

        # Write updated skill
        updated_content = build_skill_file(metadata, body)
        File.write(skill_file, updated_content)

        success("Modified skill '#{skill_name}'")
      end

      private

      def parse_frontmatter(content)
        if content.match?(/\A---\s*\n(.+?)\n---\s*\n/m)
          match = content.match(/\A---\s*\n(.+?)\n---\s*\n/m)
          metadata = YAML.safe_load(match[1]) || {}
          body = content.sub(/\A---\s*\n.+?\n---\s*\n/m, "").strip
          [metadata, body]
        else
          [{}, content.strip]
        end
      end

      def build_skill_file(metadata, body)
        <<~MD
          ---
          #{metadata.to_yaml.lines[1..].join}---

          #{body}
        MD
      end
    end
  end
end
