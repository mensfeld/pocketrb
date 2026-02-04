# frozen_string_literal: true

module Pocketrb
  module Skills
    # Represents a loaded skill from SKILL.md
    class Skill
      attr_reader :name, :description, :content, :path, :metadata

      def initialize(name:, description:, content:, path:, metadata: {})
        @name = name
        @description = description
        @content = content
        @path = path
        @metadata = metadata
      end

      # Check if skill should always be included in context
      def always?
        metadata[:always] == true || metadata["always"] == true
      end

      # Check if skill is available (meets requirements)
      def available?
        requires = metadata[:requires] || metadata["requires"]
        return true unless requires

        Array(requires).all? { |req| check_requirement(req) }
      end

      # Get skill triggers/keywords
      def triggers
        triggers = metadata[:triggers] || metadata["triggers"] || []
        Array(triggers)
      end

      # Check if a message should trigger this skill
      def matches?(text)
        return false if triggers.empty?

        text_lower = text.downcase
        triggers.any? { |t| text_lower.include?(t.downcase) }
      end

      # Get full prompt content for this skill
      def to_prompt
        <<~PROMPT
          <skill name="#{name}">
          #{content}
          </skill>
        PROMPT
      end

      # Summary for skills list
      def to_summary
        "- #{name}: #{description}"
      end

      private

      def check_requirement(req)
        case req
        when /^env:(.+)/
          !ENV[::Regexp.last_match(1)].nil?
        when /^file:(.+)/
          File.exist?(::Regexp.last_match(1))
        when /^tool:(.+)/
          # Would need tool registry context
          true
        else
          true
        end
      end
    end
  end
end
