# frozen_string_literal: true

require "json"
require "open3"

module Pocketrb
  module Providers
    # Claude CLI provider - uses the `claude` command as a subprocess
    # This allows using Claude Max/Pro subscription authentication
    class ClaudeCLI < Base
      MODELS = {
        "opus" => "claude-opus-4-20250514",
        "sonnet" => "claude-sonnet-4-20250514",
        "haiku" => "claude-3-5-haiku-20241022"
      }.freeze

      DEFAULT_MODEL = "sonnet"
      READ_TIMEOUT = 60
      TOTAL_TIMEOUT = 300

      def initialize(config = {})
        @config = config
        @stdin = nil
        @stdout = nil
        @stderr = nil
        @wait_thread = nil
        @stderr_thread = nil
        @mutex = Mutex.new
        validate_config!
      end

      def name
        :claude_cli
      end

      def default_model
        DEFAULT_MODEL
      end

      def available_models
        MODELS.keys
      end

      def chat(messages:, tools: nil, model: nil, temperature: 0.7, max_tokens: 4096, thinking: false)
        model ||= default_model

        @mutex.synchronize do
          start! unless running?

          prompt = build_prompt(messages, tools)
          send_message(prompt)
          response = read_response

          parse_cli_response(response, model)
        end
      rescue IOError, Errno::EPIPE => e
        stop!
        raise ProviderError, "Claude CLI error: #{e.message}"
      end

      def chat_stream(messages:, tools: nil, model: nil, temperature: 0.7, max_tokens: 4096, &block)
        model ||= default_model

        @mutex.synchronize do
          start! unless running?

          prompt = build_prompt(messages, tools)
          send_message(prompt)
          response = read_response_streaming(&block)

          parse_cli_response(response, model)
        end
      rescue IOError, Errno::EPIPE => e
        stop!
        raise ProviderError, "Claude CLI error: #{e.message}"
      end

      def start!
        return if running?

        args = [
          "claude",
          "-p",
          "--input-format", "stream-json",
          "--output-format", "stream-json",
          "--model", @config[:model] || DEFAULT_MODEL,
          "--verbose"
        ]

        # Add autonomous/dangerous flags if configured or via ENV
        # This skips all permission prompts - use only in trusted/sandboxed environments
        if autonomous_mode?
          args << "--allow-dangerously-skip-permissions"
          args << "--dangerously-skip-permissions"
          Pocketrb.logger.info("Autonomous mode enabled - skipping permission prompts")
        end

        # Custom permission mode if specified
        args += ["--permission-mode", @config[:permission_mode]] if @config[:permission_mode]

        args += ["--append-system-prompt", @config[:system_prompt]] if @config[:system_prompt]

        Pocketrb.logger.info("Starting Claude CLI: #{args.join(" ")}")
        Pocketrb.logger.debug("Config: autonomous=#{@config[:autonomous]}, env=#{ENV.fetch("POCKETRB_AUTONOMOUS",
                                                                                           nil)}")
        @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(*args)

        # Start stderr reader thread to capture errors
        @stderr_thread = Thread.new do
          while (line = @stderr.gets)
            Pocketrb.logger.warn("Claude CLI stderr: #{line.strip}")
          end
        rescue IOError
          # Expected when stderr is closed
        end
      end

      def autonomous_mode?
        @config[:autonomous] ||
          @config[:dangerously_skip_permissions] ||
          ENV["POCKETRB_AUTONOMOUS"] == "1" ||
          ENV["POCKETRB_AUTONOMOUS"] == "true"
      end

      def stop!
        @stdin&.close
        @stdout&.close
        @stderr&.close
        @wait_thread&.kill
        @stderr_thread&.kill
        @stdin = @stdout = @stderr = @wait_thread = @stderr_thread = nil
      end

      def running?
        @wait_thread&.alive? || false
      end

      protected

      def supported_features
        %i[tools streaming thinking]
      end

      def validate_config!
        # Check if claude CLI is available
        return if system("which claude > /dev/null 2>&1")

        raise ConfigurationError, "Claude CLI not found. Install with: npm install -g @anthropic-ai/claude-code"
      end

      private

      def build_prompt(messages, tools)
        # Build content blocks from messages, preserving images
        content_blocks = []

        messages.each do |msg|
          content = msg.content
          if content.is_a?(Array)
            # Handle content blocks (text + media)
            content.each do |block|
              if block.is_a?(Hash) && block[:type] == "media"
                # Convert media to image block
                media = block[:media]
                if media&.image?
                  image_block = format_image_for_cli(media)
                  content_blocks << image_block if image_block
                else
                  content_blocks << { type: "text", text: "[Attached: #{media&.filename || "file"}]" }
                end
              elsif block.is_a?(Hash) && block[:type] == "text"
                content_blocks << { type: "text", text: block[:text] }
              elsif block.is_a?(String)
                content_blocks << { type: "text", text: block }
              end
            end
          elsif content.is_a?(String) && !content.empty?
            content_blocks << { type: "text", text: content }
          end
        end

        # Add tool descriptions if provided
        if tools && !tools.empty?
          tool_desc = tools.map do |t|
            func = t[:function] || t
            name = func[:name]
            desc = func[:description]
            params = func[:parameters] || func[:input_schema] || {}
            props = params[:properties] || params["properties"] || {}
            param_names = props.keys.join(", ")
            "- #{name}(#{param_names}): #{desc}"
          end.join("\n")

          tool_prompt = <<~PROMPT
            You have these tools available. To use a tool, respond with a JSON block:
            ```json
            {"tool": "tool_name", "input": {"param": "value"}}
            ```

            Available tools:
            #{tool_desc}

            User request:
          PROMPT

          # Prepend tool instructions to content
          content_blocks.unshift({ type: "text", text: tool_prompt })
        end

        # Return content blocks (or just text if no images)
        if content_blocks.all? { |b| b[:type] == "text" }
          content_blocks.map { |b| b[:text] }.join("\n\n")
        else
          content_blocks
        end
      end

      def format_image_for_cli(media)
        return nil unless media&.image?

        # Get base64 data
        data = if media.data
                 media.data
               elsif media.path && File.exist?(media.path)
                 require "base64"
                 Base64.strict_encode64(File.binread(media.path))
               end

        return nil unless data

        {
          type: "image",
          source: {
            type: "base64",
            media_type: media.mime_type,
            data: data
          }
        }
      end

      def send_message(content)
        message = {
          type: "user",
          message: { role: "user", content: content }
        }
        @stdin.puts(message.to_json)
        @stdin.flush
      end

      def read_response
        result_text = ""
        usage_data = {}
        start_time = Time.now
        events_received = 0

        loop do
          elapsed = Time.now - start_time
          if elapsed > TOTAL_TIMEOUT
            Pocketrb.logger.error("Claude CLI timeout after #{elapsed.to_i}s, received #{events_received} events")
            Pocketrb.logger.error("Process alive: #{@wait_thread&.alive?}, partial response: #{result_text[0..200]}")
            break
          end

          line = read_line_with_timeout
          if line.nil?
            Pocketrb.logger.debug("No more output from Claude CLI after #{events_received} events")
            break
          end

          event = parse_event(line)
          next unless event

          events_received += 1
          Pocketrb.logger.debug("Claude CLI event ##{events_received}: #{event["type"]}")

          case event["type"]
          when "assistant"
            result_text += extract_text_from_event(event)
          when "result"
            result_text = event["result"] if event["result"] && !event["result"].empty?
            usage_data = event["usage"] || {}
            break
          when "error"
            raise ProviderError, "Claude CLI error: #{event["error"] || event["message"]}"
          end
        end

        { content: result_text, usage: usage_data }
      end

      def read_response_streaming(&block)
        result_text = ""
        usage_data = {}
        start_time = Time.now

        loop do
          break if Time.now - start_time > TOTAL_TIMEOUT

          line = read_line_with_timeout
          break if line.nil?

          event = parse_event(line)
          next unless event

          case event["type"]
          when "assistant"
            chunk = extract_text_from_event(event)
            result_text += chunk
            block&.call(chunk) unless chunk.empty?
          when "result"
            result_text = event["result"] if event["result"] && !event["result"].empty?
            usage_data = event["usage"] || {}
            break
          when "error"
            raise ProviderError, "Claude CLI error: #{event["error"] || event["message"]}"
          end
        end

        { content: result_text, usage: usage_data }
      end

      def read_line_with_timeout
        Timeout.timeout(READ_TIMEOUT) { @stdout.gets }
      rescue Timeout::Error
        nil
      end

      def parse_event(line)
        return nil if line.nil? || line.strip.empty?

        JSON.parse(line.strip)
      rescue JSON::ParserError
        nil
      end

      def extract_text_from_event(event)
        text = ""
        if event.dig("message", "content")
          event["message"]["content"].each do |block|
            text += block["text"] if block["type"] == "text"
          end
        end
        text
      end

      def parse_cli_response(response, model)
        content = response[:content]
        usage_data = response[:usage] || {}

        # Check for tool calls in the response
        tool_calls = extract_tool_calls(content)

        usage = Usage.new(
          input_tokens: usage_data["input_tokens"] || 0,
          output_tokens: usage_data["output_tokens"] || 0,
          cache_read: nil,
          cache_write: nil
        )

        # If there are tool calls, remove them from content
        content = content.gsub(/```json\s*\{.*?"tool".*?\}\s*```/m, "").strip if tool_calls.any?

        LLMResponse.new(
          content: content.empty? ? nil : content,
          tool_calls: tool_calls,
          usage: usage,
          stop_reason: tool_calls.any? ? :tool_use : :end_turn,
          model: MODELS[model] || model,
          thinking: nil
        )
      end

      def extract_tool_calls(text)
        return [] unless text

        tool_calls = []

        # Look for JSON tool calls in code blocks
        text.scan(/```json\s*(\{.*?"tool".*?\})\s*```/m) do |match|
          parsed = JSON.parse(match[0])
          if parsed["tool"]
            tool_calls << ToolCall.new(
              id: "cli_#{SecureRandom.hex(8)}",
              name: parsed["tool"],
              arguments: parsed["input"] || {}
            )
          end
        rescue JSON::ParserError
          # Skip malformed JSON
        end

        # Also try inline JSON
        if tool_calls.empty?
          text.scan(/\{"tool"\s*:\s*"\w+"[^}]*\}/m) do |match|
            parsed = JSON.parse(match)
            if parsed["tool"]
              tool_calls << ToolCall.new(
                id: "cli_#{SecureRandom.hex(8)}",
                name: parsed["tool"],
                arguments: parsed["input"] || {}
              )
            end
          rescue JSON::ParserError
            # Skip malformed JSON
          end
        end

        tool_calls
      end
    end
  end
end
