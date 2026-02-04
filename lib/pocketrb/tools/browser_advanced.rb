# frozen_string_literal: true

require_relative "browser_session"

module Pocketrb
  module Tools
    # Enhanced browser tool with sessions and tabs
    class BrowserAdvanced < Base
      ACTIONS = %w[
        new_tab close_tab focus_tab list_tabs
        navigate back forward refresh
        click type hover scroll
        screenshot snapshot
        execute_js wait
        get_text get_attribute
        fill_form select_option
        press_key
      ].freeze

      def name
        "browser"
      end

      def description
        <<~DESC.strip
          Browse the web with a persistent browser session. Supports multiple tabs,
          navigation, clicking, typing, screenshots, and JavaScript execution.
          The browser stays open between calls for efficient multi-step browsing.
        DESC
      end

      def parameters
        {
          type: "object",
          properties: {
            action: {
              type: "string",
              enum: ACTIONS,
              description: "Browser action to perform"
            },
            url: {
              type: "string",
              description: "URL for navigation or new tab"
            },
            tab_id: {
              type: "string",
              description: "Tab ID (uses active tab if not specified)"
            },
            selector: {
              type: "string",
              description: "CSS or XPath selector for element"
            },
            text: {
              type: "string",
              description: "Text to type or search for"
            },
            key: {
              type: "string",
              description: "Key to press (Enter, Tab, Escape, etc.)"
            },
            javascript: {
              type: "string",
              description: "JavaScript code to execute"
            },
            attribute: {
              type: "string",
              description: "Element attribute to get"
            },
            options: {
              type: "object",
              description: "Additional options (timeout, wait_until, etc.)"
            },
            form_data: {
              type: "object",
              description: "Form fields to fill: {selector: value, ...}"
            },
            scroll_to: {
              type: "string",
              enum: %w[top bottom element],
              description: "Where to scroll"
            },
            full_page: {
              type: "boolean",
              description: "Take full page screenshot"
            }
          },
          required: ["action"]
        }
      end

      def available?
        # Check if playwright is available
        system("which npx > /dev/null 2>&1") || system("which playwright > /dev/null 2>&1")
      end

      def execute(action:, **args)
        case action
        # Tab management
        when "new_tab"
          new_tab(args[:url])
        when "close_tab"
          close_tab(args[:tab_id])
        when "focus_tab"
          focus_tab(args[:tab_id])
        when "list_tabs"
          list_tabs

        # Navigation
        when "navigate"
          navigate(args[:url], args[:options] || {})
        when "back"
          go_back
        when "forward"
          go_forward
        when "refresh"
          refresh_page

        # Interaction
        when "click"
          click_element(args[:selector], args[:options] || {})
        when "type"
          type_text(args[:selector], args[:text], args[:options] || {})
        when "hover"
          hover_element(args[:selector])
        when "scroll"
          scroll_page(args[:scroll_to], args[:selector])
        when "press_key"
          press_key(args[:key], args[:selector])
        when "fill_form"
          fill_form(args[:form_data])
        when "select_option"
          select_option(args[:selector], args[:text])

        # Content
        when "screenshot"
          take_screenshot(args[:full_page])
        when "snapshot"
          get_snapshot
        when "get_text"
          get_text(args[:selector])
        when "get_attribute"
          get_attribute(args[:selector], args[:attribute])
        when "execute_js"
          execute_javascript(args[:javascript])

        # Wait
        when "wait"
          wait_for(args[:selector], args[:options] || {})

        else
          error("Unknown action: #{action}")
        end
      rescue Playwright::TimeoutError => e
        error("Timeout: #{e.message}")
      rescue Playwright::Error => e
        error("Browser error: #{e.message}")
      rescue StandardError => e
        error("Error: #{e.message}")
      end

      private

      def session
        BrowserSession.instance
      end

      def page(tab_id = nil)
        if tab_id
          session.tabs[tab_id]&.dig(:page)
        else
          session.active_page
        end
      end

      def ensure_page!
        p = page
        return p if p

        # Auto-create a tab if none exists
        session.new_tab
        session.active_page
      end

      # === Tab Management ===

      def new_tab(url)
        tab_id = session.new_tab(url: url)
        info = session.tab_info(tab_id)

        if url
          success("Opened new tab #{tab_id}: #{info[:title]}\nURL: #{info[:url]}")
        else
          success("Opened new empty tab: #{tab_id}")
        end
      end

      def close_tab(tab_id)
        tab_id ||= session.active_tab_id
        return error("No tab to close") unless tab_id

        if session.close_tab(tab_id)
          remaining = session.tabs.size
          success("Closed tab #{tab_id}. #{remaining} tabs remaining.")
        else
          error("Tab not found: #{tab_id}")
        end
      end

      def focus_tab(tab_id)
        return error("Tab ID required") unless tab_id

        if session.focus_tab(tab_id)
          info = session.tab_info(tab_id)
          success("Focused tab #{tab_id}: #{info[:title]}")
        else
          error("Tab not found: #{tab_id}")
        end
      end

      def list_tabs
        tabs = session.list_tabs
        return "No tabs open. Use action 'new_tab' to open one." if tabs.empty?

        lines = ["Open tabs (#{tabs.size}):"]
        tabs.each do |tab|
          marker = tab[:active] ? "→" : " "
          lines << "#{marker} [#{tab[:id]}] #{tab[:title]}"
          lines << "    #{tab[:url]}"
        end
        lines.join("\n")
      end

      # === Navigation ===

      def navigate(url, options)
        return error("URL required") unless url

        p = ensure_page!
        wait_until = options[:wait_until] || "domcontentloaded"

        p.goto(url, wait_until: wait_until)
        session.update_tab_info(session.active_tab_id)

        title = p.title
        success("Navigated to: #{title}\nURL: #{p.url}")
      end

      def go_back
        p = ensure_page!
        p.go_back
        session.update_tab_info(session.active_tab_id)
        success("Navigated back to: #{p.title}")
      end

      def go_forward
        p = ensure_page!
        p.go_forward
        session.update_tab_info(session.active_tab_id)
        success("Navigated forward to: #{p.title}")
      end

      def refresh_page
        p = ensure_page!
        p.reload
        success("Page refreshed: #{p.title}")
      end

      # === Interaction ===

      def click_element(selector, options)
        return error("Selector required") unless selector

        p = ensure_page!
        timeout = options[:timeout] || 5000

        p.click(selector, timeout: timeout)
        success("Clicked: #{selector}")
      end

      def type_text(selector, text, _options)
        return error("Selector and text required") unless selector && text

        p = ensure_page!

        p.fill(selector, text)
        success("Typed into #{selector}: #{text[0..50]}#{"..." if text.length > 50}")
      end

      def hover_element(selector)
        return error("Selector required") unless selector

        p = ensure_page!
        p.hover(selector)
        success("Hovering over: #{selector}")
      end

      def scroll_page(direction, selector)
        p = ensure_page!

        case direction
        when "top"
          p.evaluate("window.scrollTo(0, 0)")
          success("Scrolled to top")
        when "bottom"
          p.evaluate("window.scrollTo(0, document.body.scrollHeight)")
          success("Scrolled to bottom")
        when "element"
          return error("Selector required for element scroll") unless selector

          p.evaluate("document.querySelector('#{selector}')?.scrollIntoView({behavior: 'smooth'})")
          success("Scrolled to element: #{selector}")
        else
          p.evaluate("window.scrollBy(0, 500)")
          success("Scrolled down")
        end
      end

      def press_key(key, selector)
        return error("Key required") unless key

        p = ensure_page!

        if selector
          p.press(selector, key)
        else
          p.keyboard.press(key)
        end

        success("Pressed key: #{key}")
      end

      def fill_form(form_data)
        return error("Form data required") unless form_data.is_a?(Hash)

        p = ensure_page!
        filled = []

        form_data.each do |selector, value|
          p.fill(selector.to_s, value.to_s)
          filled << selector
        end

        success("Filled #{filled.size} form fields: #{filled.join(", ")}")
      end

      def select_option(selector, value)
        return error("Selector and value required") unless selector && value

        p = ensure_page!
        p.select_option(selector, value: value)
        success("Selected '#{value}' in #{selector}")
      end

      # === Content ===

      def take_screenshot(full_page)
        p = ensure_page!

        # Save to workspace
        filename = "screenshot_#{Time.now.strftime("%Y%m%d_%H%M%S")}.png"
        path = resolve_path(filename)

        p.screenshot(path: path.to_s, full_page: full_page || false)
        success("Screenshot saved: #{path}")
      end

      def get_snapshot
        p = ensure_page!

        # Get a simplified view of the page
        title = p.title
        url = p.url

        # Get visible text content
        content = p.evaluate(<<~JS)
          (() => {
            const walker = document.createTreeWalker(
              document.body,
              NodeFilter.SHOW_TEXT,
              { acceptNode: (node) => {
                const parent = node.parentElement;
                if (!parent) return NodeFilter.FILTER_REJECT;
                const style = getComputedStyle(parent);
                if (style.display === 'none' || style.visibility === 'hidden') {
                  return NodeFilter.FILTER_REJECT;
                }
                return node.textContent.trim() ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
              }}
            );
            const texts = [];
            while (walker.nextNode()) {
              texts.push(walker.currentNode.textContent.trim());
            }
            return texts.join(' ').substring(0, 5000);
          })()
        JS

        # Get interactive elements
        elements = p.evaluate(<<~JS)
          (() => {
            const items = [];
            document.querySelectorAll('a, button, input, select, textarea, [onclick], [role="button"]').forEach((el, i) => {
              if (i > 50) return;
              const rect = el.getBoundingClientRect();
              if (rect.width === 0 || rect.height === 0) return;

              let desc = el.textContent?.trim()?.substring(0, 50) || el.getAttribute('aria-label') || el.getAttribute('title') || el.getAttribute('placeholder') || '';
              const tag = el.tagName.toLowerCase();
              const type = el.getAttribute('type') || '';

              items.push(`[${i}] <${tag}${type ? ' type=' + type : ''}> ${desc}`);
            });
            return items.join('\\n');
          })()
        JS

        <<~SNAPSHOT
          # Page Snapshot

          **Title:** #{title}
          **URL:** #{url}

          ## Content Summary
          #{content[0..2000]}#{"...(truncated)" if content.length > 2000}

          ## Interactive Elements
          #{elements}
        SNAPSHOT
      end

      def get_text(selector)
        p = ensure_page!

        text = p.text_content(selector || "body")

        text = "#{text[0..3000]}...(truncated)" if text.length > 3000
        success(text)
      end

      def get_attribute(selector, attribute)
        return error("Selector and attribute required") unless selector && attribute

        p = ensure_page!
        value = p.get_attribute(selector, attribute)
        success("#{selector}[#{attribute}] = #{value}")
      end

      def execute_javascript(code)
        return error("JavaScript code required") unless code

        p = ensure_page!
        result = p.evaluate(code)
        success("Result: #{result.inspect}")
      end

      # === Wait ===

      def wait_for(selector, options)
        return error("Selector required") unless selector

        p = ensure_page!
        timeout = options[:timeout] || 10_000
        state = options[:state] || "visible"

        p.wait_for_selector(selector, state: state, timeout: timeout)
        success("Element found: #{selector}")
      end
    end
  end
end
