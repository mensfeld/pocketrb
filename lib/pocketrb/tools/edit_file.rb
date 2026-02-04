# frozen_string_literal: true

module Pocketrb
  module Tools
    # Edit a file with search/replace
    class EditFile < Base
      def name
        "edit_file"
      end

      def description
        "Edit a file by replacing specific text. The old_string must match exactly (including whitespace and indentation). Use for precise edits rather than rewriting entire files."
      end

      def parameters
        {
          type: "object",
          properties: {
            path: {
              type: "string",
              description: "Path to the file to edit"
            },
            old_string: {
              type: "string",
              description: "The exact text to find and replace (must match exactly)"
            },
            new_string: {
              type: "string",
              description: "The text to replace it with"
            },
            replace_all: {
              type: "boolean",
              description: "Replace all occurrences instead of just the first (default: false)"
            }
          },
          required: %w[path old_string new_string]
        }
      end

      def execute(path:, old_string:, new_string:, replace_all: false)
        resolved = validate_path!(path)

        return error("Not a file: #{path}") unless resolved.file?

        content = File.read(resolved)

        # Check if old_string exists
        unless content.include?(old_string)
          # Try to provide helpful feedback
          return error(suggest_match(content, old_string))
        end

        # Check for uniqueness if not replace_all
        if !replace_all && content.scan(old_string).length > 1
          return error("old_string is not unique in the file (found #{content.scan(old_string).length} occurrences). Use replace_all: true or provide a more specific match.")
        end

        # Perform replacement
        new_content = if replace_all
                        content.gsub(old_string, new_string)
                      else
                        content.sub(old_string, new_string)
                      end

        # Write back
        File.write(resolved, new_content)

        count = replace_all ? content.scan(old_string).length : 1
        success("Replaced #{count} occurrence(s) in #{path}")
      rescue Errno::ENOENT
        error("File not found: #{path}")
      rescue Errno::EACCES
        error("Permission denied: #{path}")
      end

      private

      def suggest_match(content, old_string)
        # Try to find similar content
        lines = content.lines
        old_lines = old_string.lines

        return "old_string not found in file" if old_lines.empty?

        first_line = old_lines.first.strip

        # Find lines containing the first line's content
        matches = lines.each_with_index.filter_map do |line, idx|
          [line, idx + 1] if line.include?(first_line) || first_line.include?(line.strip)
        end

        if matches.any?
          match_info = matches.first(3).map { |line, num| "Line #{num}: #{line.strip[0..60]}" }.join("\n")
          "old_string not found. Similar content found at:\n#{match_info}\n\nCheck for whitespace or indentation differences."
        else
          "old_string not found in file. Ensure the text matches exactly, including all whitespace and indentation."
        end
      end
    end
  end
end
