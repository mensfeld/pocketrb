# frozen_string_literal: true

module Pocketrb
  class CLI
    # Init command - initializes a new Pocketrb workspace
    class Init < Base
      desc "init", "Initialize a new Pocketrb workspace"
      # Initializes a new Pocketrb workspace with config and default structure
      # @return [void]
      def call
        workspace = resolve_workspace
        config_dir = workspace.join(".pocketrb")

        if config_dir.exist?
          say "Workspace already initialized at #{workspace}", :yellow
          return
        end

        FileUtils.mkdir_p(config_dir)
        FileUtils.mkdir_p(workspace.join("skills"))

        Pocketrb::Config.new(workspace: workspace).save!

        # Create default TOOLS.md
        tools_file = workspace.join("TOOLS.md")
        File.write(tools_file, default_tools_content) unless tools_file.exist?

        say "Initialized Pocketrb workspace at #{workspace}", :green
        say "  - Created .pocketrb/config.yml"
        say "  - Created skills/"
        say "\nNext steps:"
        say "  1. Set your API key: export ANTHROPIC_API_KEY=your-key"
        say "  2. Start chatting: pocketrb chat"
      end

      default_task :call
    end
  end
end
