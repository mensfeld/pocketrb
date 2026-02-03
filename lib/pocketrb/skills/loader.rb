# frozen_string_literal: true

require "yaml"

module Pocketrb
  module Skills
    # Loads and manages skills from SKILL.md files
    class Loader
      SKILL_FILE = "SKILL.md"
      FRONTMATTER_REGEX = /\A---\s*\n(.+?)\n---\s*\n/m

      attr_reader :workspace, :builtin_dir

      def initialize(workspace:, builtin_dir: nil)
        @workspace = Pathname.new(workspace)
        @builtin_dir = if builtin_dir
                         Pathname.new(builtin_dir)
                       else
                         # Default to gem's builtin skills directory
                         Pocketrb.root.join("lib", "pocketrb", "skills", "builtin")
                       end
        @skills_cache = {}
      end

      # List all available skills
      # @param filter_unavailable [Boolean] Exclude unavailable skills
      # @return [Array<Skill>]
      def list_skills(filter_unavailable: true)
        skills = []

        # Load builtin skills
        skills.concat(load_from_directory(@builtin_dir)) if @builtin_dir&.exist?

        # Load workspace skills
        skills_dir = @workspace.join("skills")
        skills.concat(load_from_directory(skills_dir)) if skills_dir.exist?

        # Filter unavailable if requested
        skills = skills.select(&:available?) if filter_unavailable

        skills
      end

      # Load a specific skill by name
      # @param name [String] Skill name
      # @return [Skill|nil]
      def load_skill(name)
        @skills_cache[name] ||= find_and_load_skill(name)
      end

      # Get skills that should always be included
      # @return [Array<Skill>]
      def get_always_skills
        list_skills.select(&:always?)
      end

      # Get skills triggered by a message
      # @param text [String] Message text
      # @return [Array<Skill>]
      def get_triggered_skills(text)
        list_skills.select { |s| s.matches?(text) }
      end

      # Build XML summary of all skills for context
      # @return [String]
      def build_skills_summary
        skills = list_skills

        return "" if skills.empty?

        <<~XML
          <available-skills>
          #{skills.map(&:to_summary).join("\n")}
          </available-skills>
        XML
      end

      # Build full prompt content for specific skills
      # @param skill_names [Array<String>] Skills to include
      # @return [String]
      def build_skills_prompt(skill_names)
        skills = skill_names.map { |name| load_skill(name) }.compact
        skills.map(&:to_prompt).join("\n\n")
      end

      # Clear the skills cache
      def clear_cache!
        @skills_cache.clear
      end

      private

      def load_from_directory(dir)
        return [] unless dir.exist?

        skills = []

        # Direct SKILL.md in skills directory
        skill_file = dir.join(SKILL_FILE)
        skills << parse_skill_file(skill_file) if skill_file.exist?

        # Subdirectories with SKILL.md
        Dir.glob(dir.join("*", SKILL_FILE)).each do |path|
          skill = parse_skill_file(Pathname.new(path))
          skills << skill if skill
        end

        skills.compact
      end

      def find_and_load_skill(name)
        # Check workspace skills
        skill_path = @workspace.join("skills", name, SKILL_FILE)
        return parse_skill_file(skill_path) if skill_path.exist?

        # Check builtin skills
        if @builtin_dir
          builtin_path = @builtin_dir.join(name, SKILL_FILE)
          return parse_skill_file(builtin_path) if builtin_path.exist?
        end

        nil
      end

      def parse_skill_file(path)
        return nil unless path.exist?

        content = File.read(path)
        metadata, body = extract_frontmatter(content)

        name = metadata["name"] || path.dirname.basename.to_s
        description = metadata["description"] || extract_description(body)

        Skill.new(
          name: name,
          description: description,
          content: body,
          path: path,
          metadata: metadata
        )
      rescue StandardError => e
        Pocketrb.logger.error("Failed to parse skill at #{path}: #{e.message}")
        nil
      end

      def extract_frontmatter(content)
        if content.match?(FRONTMATTER_REGEX)
          match = content.match(FRONTMATTER_REGEX)
          metadata = YAML.safe_load(match[1]) || {}
          body = content.sub(FRONTMATTER_REGEX, "").strip
          [metadata, body]
        else
          [{}, content.strip]
        end
      end

      def extract_description(body)
        # Extract first line or paragraph as description
        first_line = body.lines.first&.strip
        first_line&.gsub(/^#+\s*/, "") || "No description"
      end
    end
  end
end
