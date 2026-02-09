# frozen_string_literal: true

require "playwright"

module Pocketrb
  module Tools
    # Browser automation tool using Playwright
    class Browser < Base
      # Tool name
      # @return [String]
      def name
        "browser"
      end

      # Tool description
      # @return [String]
      def description
        "Automate browser interactions using headless Chromium. Can navigate to URLs, extract text content, take screenshots, interact with elements, and execute JavaScript. Use this for web scraping, research, testing, or any task requiring web browsing."
      end

      # Parameter schema
      # @return [Hash]
      def parameters
        {
          type: "object",
          properties: {
            action: {
              type: "string",
              description: "Action to perform",
              enum: %w[navigate extract_text screenshot click type execute_js]
            },
            url: {
              type: "string",
              description: "URL to navigate to (required for navigate action)"
            },
            selector: {
              type: "string",
              description: "CSS selector for element interaction (required for click, type actions)"
            },
            text: {
              type: "string",
              description: "Text to type (required for type action)"
            },
            javascript: {
              type: "string",
              description: "JavaScript code to execute (required for execute_js action)"
            },
            screenshot_path: {
              type: "string",
              description: "Path to save screenshot (optional, defaults to workspace/screenshot.png)"
            },
            wait_time: {
              type: "integer",
              description: "Milliseconds to wait after navigation (default: 1000)"
            }
          },
          required: ["action"]
        }
      end

      # Execute browser automation action
      # @param action [String] Action to perform (navigate, extract_text, screenshot, click, type, execute_js)
      # @param url [String, nil] URL to navigate to
      # @param selector [String, nil] CSS selector for element targeting
      # @param text [String, nil] Text to type into an element
      # @param javascript [String, nil] JavaScript code to execute in browser context
      # @param screenshot_path [String, nil] File path for saving screenshot
      # @param wait_time [Integer] Milliseconds to wait after navigation
      # @option _kwargs [Object] * Additional action-specific options
      # @return [String] Action result
      def execute(action:, url: nil, selector: nil, text: nil, javascript: nil, screenshot_path: nil, wait_time: 1000,
                  **_kwargs)
        case action
        when "navigate"
          return error("URL required for navigate action") unless url

          navigate_and_extract(url, wait_time)
        when "extract_text"
          extract_text_from_page
        when "screenshot"
          take_screenshot(screenshot_path || "screenshot.png")
        when "click"
          return error("Selector required for click action") unless selector

          click_element(selector, wait_time)
        when "type"
          return error("Selector and text required for type action") unless selector && text

          type_into_element(selector, text, wait_time)
        when "execute_js"
          return error("JavaScript required for execute_js action") unless javascript

          execute_javascript(javascript)
        else
          error("Unknown action: #{action}")
        end
      rescue Playwright::Error => e
        error("Playwright error: #{e.message}")
      rescue StandardError => e
        error("Unexpected error: #{e.message}")
      end

      private

      def with_browser
        Playwright.create(playwright_cli_executable_path: "npx playwright") do |playwright|
          playwright.chromium.launch(headless: true) do |browser|
            page = browser.new_page
            @current_page = page
            yield page
          end
        end
      ensure
        @current_page = nil
      end

      def navigate_and_extract(url, wait_time)
        with_browser do |page|
          page.goto(url)
          page.wait_for_timeout(wait_time)

          title = page.title
          content = page.text_content("body")

          success("Title: #{title}\n\nContent:\n#{content[0..2000]}#{"...(truncated)" if content.length > 2000}")
        end
      end

      def extract_text_from_page
        return error("No page is currently loaded. Use navigate action first.") unless @current_page

        content = @current_page.text_content("body")
        success(content[0..5000] + (content.length > 5000 ? "...(truncated)" : ""))
      end

      def take_screenshot(path)
        with_browser do |page|
          screenshot_path = resolve_path(path)
          page.screenshot(path: screenshot_path.to_s)
          success("Screenshot saved to #{screenshot_path}")
        end
      end

      def click_element(selector, wait_time)
        with_browser do |page|
          page.click(selector)
          page.wait_for_timeout(wait_time)
          success("Clicked element: #{selector}")
        end
      end

      def type_into_element(selector, text, wait_time)
        with_browser do |page|
          page.fill(selector, text)
          page.wait_for_timeout(wait_time)
          success("Typed into element: #{selector}")
        end
      end

      def execute_javascript(javascript)
        with_browser do |page|
          result = page.evaluate(javascript)
          success("JavaScript executed. Result: #{result.inspect}")
        end
      end
    end
  end
end
