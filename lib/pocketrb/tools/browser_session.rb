# frozen_string_literal: true

require "singleton"

module Pocketrb
  module Tools
    # Manages persistent browser sessions with tabs
    class BrowserSession
      include Singleton

      attr_reader :tabs, :active_tab_id

      def initialize
        @playwright = nil
        @browser = nil
        @context = nil
        @tabs = {} # id => { page:, url:, title: }
        @active_tab_id = nil
        @tab_counter = 0
        @mutex = Mutex.new
        @started = false
      end

      def start!
        return if @started

        @mutex.synchronize do
          return if @started

          require "playwright"
          @playwright = Playwright.create(playwright_cli_executable_path: find_playwright_cli)
          @browser = @playwright.chromium.launch(
            headless: ENV["BROWSER_HEADLESS"] != "false",
            args: ["--no-sandbox", "--disable-setuid-sandbox"]
          )
          @context = @browser.new_context(
            viewport: { width: 1280, height: 800 },
            user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
          )
          @started = true
          Pocketrb.logger.info("Browser session started")
        end
      end

      def stop!
        @mutex.synchronize do
          @tabs.each_value do |tab|
            tab[:page]&.close
          rescue StandardError
            nil
          end
          @tabs.clear
          @context&.close
          @browser&.close
          @playwright&.stop
          @playwright = nil
          @browser = nil
          @context = nil
          @active_tab_id = nil
          @started = false
          Pocketrb.logger.info("Browser session stopped")
        end
      end

      def started?
        @started
      end

      # Create a new tab
      def new_tab(url: nil)
        start! unless started?

        @mutex.synchronize do
          @tab_counter += 1
          tab_id = "tab_#{@tab_counter}"

          page = @context.new_page
          page.goto(url) if url

          @tabs[tab_id] = {
            page: page,
            url: url,
            title: page.title,
            created_at: Time.now
          }
          @active_tab_id = tab_id

          tab_id
        end
      end

      # Close a tab
      def close_tab(tab_id)
        @mutex.synchronize do
          tab = @tabs.delete(tab_id)
          return false unless tab

          tab[:page]&.close
          @active_tab_id = @tabs.keys.last if @active_tab_id == tab_id
          true
        end
      end

      # Focus a tab
      def focus_tab(tab_id)
        @mutex.synchronize do
          return false unless @tabs.key?(tab_id)

          @active_tab_id = tab_id
          @tabs[tab_id][:page].bring_to_front
          true
        end
      end

      # Get active page
      def active_page
        return nil unless @active_tab_id

        @tabs[@active_tab_id]&.dig(:page)
      end

      # Get tab info
      def tab_info(tab_id)
        tab = @tabs[tab_id]
        return nil unless tab

        {
          id: tab_id,
          url: tab[:page].url,
          title: tab[:page].title,
          active: tab_id == @active_tab_id
        }
      end

      # List all tabs
      def list_tabs
        @tabs.map do |id, tab|
          {
            id: id,
            url: tab[:page].url,
            title: tab[:page].title,
            active: id == @active_tab_id
          }
        end
      end

      # Update tab metadata
      def update_tab_info(tab_id)
        tab = @tabs[tab_id]
        return unless tab

        tab[:url] = tab[:page].url
        tab[:title] = tab[:page].title
      end

      private

      def find_playwright_cli
        # Try common locations
        ["npx playwright", "playwright", "node_modules/.bin/playwright"].each do |cmd|
          return cmd if system("which #{cmd.split.first} > /dev/null 2>&1")
        end
        "npx playwright"
      end
    end
  end
end
