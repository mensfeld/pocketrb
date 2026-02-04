# frozen_string_literal: true

module Pocketrb
  class CLI
    # Version command - displays current Pocketrb version
    class Version < Base
      desc "version", "Show version"
      # Displays the current Pocketrb version
      # @return [void]
      def call
        say "Pocketrb #{Pocketrb::VERSION}"
      end

      # Thor doesn't support default task name, so alias it
      default_task :call
    end
  end
end
