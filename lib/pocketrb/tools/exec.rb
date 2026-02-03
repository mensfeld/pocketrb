# frozen_string_literal: true

require "open3"
require "timeout"

module Pocketrb
  module Tools
    # Execute shell commands with smart timeout and background job support
    class Exec < Base
      # Per-operation timeouts (seconds)
      TIMEOUTS = {
        simple: 30,     # Quick commands (ls, cat, echo)
        standard: 120,  # Normal shell commands
        complex: 300    # Builds, installs
      }.freeze

      DEFAULT_TIMEOUT = TIMEOUTS[:standard]
      MAX_OUTPUT_SIZE = 100_000

      # Quick commands that should finish fast
      QUICK_PATTERNS = [
        /^(ls|cat|head|tail|echo|pwd|whoami|date|hostname|env)\b/i,
        /^cd\s/i,
        /^which\s/i,
        /^type\s/i,
        /^file\s/i,
        /^stat\s/i,
        /^test\s/i,
        /^\[/ # test bracket syntax
      ].freeze

      def name
        "exec"
      end

      def description
        "Execute a shell command. Long-running commands (apt install, npm install, etc.) auto-run in background. Use for git, npm, make, and other development tools."
      end

      def parameters
        {
          type: "object",
          properties: {
            command: {
              type: "string",
              description: "The shell command to execute"
            },
            timeout: {
              type: "integer",
              description: "Timeout in seconds (default: auto-detected, max: 600)"
            },
            working_dir: {
              type: "string",
              description: "Working directory for the command (defaults to workspace)"
            },
            background: {
              type: "boolean",
              description: "Force run in background (default: auto-detected for long commands)"
            }
          },
          required: ["command"]
        }
      end

      def execute(command:, timeout: nil, working_dir: nil, background: nil)
        work_dir = resolve_working_dir(working_dir)
        return work_dir if work_dir.is_a?(String) && work_dir.start_with?("Error:")

        return error("Command blocked for security reasons") if dangerous_command?(command)

        # Determine if should run in background
        run_background = background.nil? ? job_manager.long_running?(command) : background

        if run_background
          execute_background(command, work_dir)
        else
          execute_foreground(command, work_dir, timeout)
        end
      end

      private

      def job_manager
        @job_manager ||= BackgroundJobManager.new(workspace: workspace)
      end

      def resolve_working_dir(working_dir)
        if working_dir
          resolved = resolve_path(working_dir)
          return error("Working directory outside workspace: #{working_dir}") unless path_allowed?(working_dir)

          resolved.to_s
        else
          workspace&.to_s || Dir.pwd
        end
      end

      def execute_background(command, work_dir)
        Pocketrb.logger.debug("Running in background: #{command}")

        result = job_manager.start(
          command: command,
          working_dir: work_dir,
          name: command[0..50]
        )

        success(<<~OUTPUT)
          Started in background (detected long-running command)
          Job ID: #{result[:job_id]}
          PID: #{result[:pid]}
          Log: #{result[:log_file]}

          Use 'jobs' tool to check status and output.
        OUTPUT
      end

      def execute_foreground(command, work_dir, explicit_timeout)
        timeout = explicit_timeout || smart_timeout(command)
        timeout = [timeout, 600].min if timeout

        Pocketrb.logger.debug("Executing: #{command} in #{work_dir} (timeout: #{timeout || "none"})")

        stdout, stderr, status = nil

        begin
          if timeout
            Timeout.timeout(timeout) do
              stdout, stderr, status = Open3.capture3(command, chdir: work_dir)
            end
          else
            stdout, stderr, status = Open3.capture3(command, chdir: work_dir)
          end
        rescue Timeout::Error
          return error("Command timed out after #{timeout} seconds. Consider using background: true for long commands.")
        end

        format_result(stdout, stderr, status)
      end

      def smart_timeout(command)
        return TIMEOUTS[:simple] if quick_command?(command)
        return nil if job_manager.long_running?(command)

        TIMEOUTS[:standard]
      end

      def quick_command?(command)
        return false if command.nil? || command.empty?

        QUICK_PATTERNS.any? { |p| command.match?(p) }
      end

      def dangerous_command?(command)
        dangerous_patterns = [
          %r{\brm\s+-rf\s+[/~]},
          /\bmkfs\b/,
          %r{\bdd\s+.*of=/dev},
          %r{>\s*/dev/sd},
          /\bshutdown\b/,
          /\breboot\b/,
          /\binit\s+0\b/,
          /:(){ :|:& };:/
        ]

        dangerous_patterns.any? { |pattern| command.match?(pattern) }
      end

      def format_result(stdout, stderr, status)
        output_parts = []

        output_parts << if status.success?
                          "Exit code: 0"
                        else
                          "Exit code: #{status.exitstatus}"
                        end

        output_parts << "STDOUT:\n#{truncate_output(stdout)}" if stdout && !stdout.empty?

        output_parts << "STDERR:\n#{truncate_output(stderr)}" if stderr && !stderr.empty?

        output_parts << "(no output)" if stdout.to_s.empty? && stderr.to_s.empty?

        output_parts.join("\n\n")
      end

      def truncate_output(output)
        return output if output.length <= MAX_OUTPUT_SIZE

        half = MAX_OUTPUT_SIZE / 2
        "#{output[0...half]}\n\n... [truncated #{output.length - MAX_OUTPUT_SIZE} characters] ...\n\n#{output[-half..]}"
      end
    end
  end
end
