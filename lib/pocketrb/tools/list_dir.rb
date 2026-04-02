# frozen_string_literal: true

module Pocketrb
  module Tools
    # List directory contents
    class ListDir < Base
      # Tool name
      # @return [String]
      def name
        "list_dir"
      end

      # Tool description
      # @return [String]
      def description
        "List the contents of a directory. Shows files and subdirectories with basic metadata."
      end

      # Parameter schema
      # @return [Hash]
      def parameters
        {
          type: "object",
          properties: {
            path: {
              type: "string",
              description: "Path to the directory to list (defaults to workspace root)"
            },
            pattern: {
              type: "string",
              description: "Glob pattern to filter results (e.g., '*.rb', '**/*.ts')"
            },
            recursive: {
              type: "boolean",
              description: "List subdirectories recursively (default: false)"
            },
            include_hidden: {
              type: "boolean",
              description: "Include hidden files (starting with .) (default: false)"
            }
          },
          required: []
        }
      end

      # Execute directory listing
      # @param path [String, nil] Directory path to list (defaults to workspace root)
      # @param pattern [String, nil] Glob pattern to filter results
      # @param recursive [Boolean] Whether to list subdirectories recursively
      # @param include_hidden [Boolean] Whether to include hidden files
      # @return [String] Formatted directory listing
      def execute(path: nil, pattern: nil, recursive: false, include_hidden: false)
        resolved = path ? validate_path!(path) : workspace

        return error("Not a directory: #{path || "workspace"}") unless resolved&.directory?

        entries = if pattern
                    glob_pattern = resolved.join(recursive ? "**" : "", pattern)
                    Dir.glob(glob_pattern)
                  elsif recursive
                    Dir.glob(resolved.join("**", "*"))
                  else
                    Dir.children(resolved).map { |e| resolved.join(e).to_s }
                  end

        # Filter hidden files
        entries = entries.reject { |e| File.basename(e).start_with?(".") } unless include_hidden

        # Sort entries
        entries.sort!

        # Format output
        output = entries.map do |entry|
          path_obj = Pathname.new(entry)
          relative = workspace ? path_obj.relative_path_from(workspace) : path_obj
          format_entry(path_obj, relative)
        end

        if output.empty?
          "Directory is empty or no matches found"
        else
          output.join("\n")
        end
      end

      private

      # Format a directory entry for display
      # @param path [Pathname] absolute path to the entry
      # @param relative [Pathname] path relative to workspace
      # @return [String] formatted entry with metadata
      def format_entry(path, relative)
        if path.directory?
          "#{relative}/"
        else
          size = format_size(path.size)
          mtime = path.mtime.strftime("%Y-%m-%d %H:%M")
          "#{relative} (#{size}, #{mtime})"
        end
      rescue StandardError
        relative.to_s
      end

      # Format byte size into human-readable units
      # @param bytes [Integer] size in bytes
      # @return [String] formatted size string (e.g. "1.5KB")
      def format_size(bytes)
        units = %w[B KB MB GB]
        unit_index = 0

        size = bytes.to_f
        while size >= 1024 && unit_index < units.length - 1
          size /= 1024
          unit_index += 1
        end

        format("%.1f%s", size, units[unit_index])
      end
    end
  end
end
