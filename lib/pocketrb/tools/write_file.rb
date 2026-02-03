# frozen_string_literal: true

module Pocketrb
  module Tools
    # Write content to a file
    class WriteFile < Base
      MAX_FILE_SIZE = 10 * 1024 * 1024 # 10MB

      def name
        "write_file"
      end

      def description
        "Write content to a file. Creates the file if it doesn't exist, or overwrites if it does. Creates parent directories as needed."
      end

      def parameters
        {
          type: "object",
          properties: {
            path: {
              type: "string",
              description: "Path to the file to write (relative to workspace or absolute)"
            },
            content: {
              type: "string",
              description: "Content to write to the file"
            }
          },
          required: %w[path content]
        }
      end

      def execute(path:, content:)
        resolved = resolve_path(path)

        return error("Path is outside workspace: #{path}") unless path_allowed?(path)

        return error("Content exceeds maximum file size (10MB)") if content.bytesize > MAX_FILE_SIZE

        # Create parent directories
        FileUtils.mkdir_p(resolved.dirname)

        # Write file
        File.write(resolved, content)

        success("Wrote #{content.lines.count} lines (#{content.bytesize} bytes) to #{path}")
      rescue Errno::EACCES
        error("Permission denied: #{path}")
      rescue Errno::ENOSPC
        error("No space left on device")
      end
    end
  end
end
