# frozen_string_literal: true

module Pocketrb
  module Tools
    # Read file contents
    class ReadFile < Base
      def name
        "read_file"
      end

      def description
        "Read the contents of a file. Returns the file content as text."
      end

      def parameters
        {
          type: "object",
          properties: {
            path: {
              type: "string",
              description: "Path to the file to read (relative to workspace or absolute)"
            },
            offset: {
              type: "integer",
              description: "Line number to start reading from (1-indexed, optional)"
            },
            limit: {
              type: "integer",
              description: "Maximum number of lines to read (optional)"
            }
          },
          required: ["path"]
        }
      end

      def execute(path:, offset: nil, limit: nil)
        resolved = validate_path!(path)

        unless resolved.file?
          return error("Not a file: #{path}")
        end

        content = File.read(resolved)
        lines = content.lines

        # Apply offset and limit
        if offset && offset > 1
          lines = lines[(offset - 1)..]
        end

        if limit
          lines = lines.first(limit)
        end

        # Add line numbers
        start_line = offset || 1
        numbered_lines = lines.each_with_index.map do |line, idx|
          "#{start_line + idx}: #{line}"
        end

        numbered_lines.join
      rescue Errno::ENOENT
        error("File not found: #{path}")
      rescue Errno::EACCES
        error("Permission denied: #{path}")
      rescue Errno::EISDIR
        error("Is a directory: #{path}")
      end
    end
  end
end
