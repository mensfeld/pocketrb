# frozen_string_literal: true

require "yaml"

module Pocketrb
  module Skills
    # Loads and manages skills from SKILL.md files
    class Loader
      # Filename for skill definition
      SKILL_FILE = "SKILL.md"
      # Regex to parse YAML frontmatter in skill files
      FRONTMATTER_REGEX = /\A---\s*\n(.+?)\n---\s*\n/m

      attr_reader :workspace, :builtin_dir

      # Initialize skills loader
      # @param workspace [String, Pathname] Workspace directory containing skills/ folder
      # @param builtin_dir [String, Pathname, nil] Directory with builtin skills (defaults to gem's builtin dir)
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
      # @return [Skill, nil]
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
        skills = skill_names.filter_map { |name| load_skill(name) }
        skills.map(&:to_prompt).join("\n\n")
      end

      # Clear the skills cache
      # @return [void]
      def clear_cache!
        @skills_cache.clear
      end

      private

      # Load all skills from a directory and its subdirectories
      # @param dir [Pathname] directory to scan for SKILL.md files
      # @return [Array<Skill>] loaded skills
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

      # Find and load a skill by name from workspace or builtin directories
      # @param name [String] skill name to find
      # @return [Skill, nil] loaded skill or nil if not found
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

      # Parse a SKILL.md file into a Skill object
      # @param path [Pathname] path to SKILL.md file
      # @return [Skill, nil] parsed skill or nil on error
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

      # Extract YAML frontmatter and body from markdown content
      # @param content [String] raw file content
      # @return [Array] two-element array of metadata Hash and body String
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

      # Extract a description from the first line of markdown body
      # @param body [String] markdown body text
      # @return [String] extracted description
      def extract_description(body)
        # Extract first line or paragraph as description
        first_line = body.lines.first&.strip
        first_line&.gsub(/^#+\s*/, "") || "No description"
      end
    end
  end
end
