# frozen_string_literal: true

require "async"

module Pocketrb
  # Agent module provides the core agentic loop and context management
  module Agent
    # Core agent processing loop
    class Loop
      attr_reader :bus, :provider, :tools, :sessions, :context, :model, :max_iterations, :workspace, :memory_dir,
                  :memory, :compaction

      # Initialize the agent loop
      # @param bus [Bus::MessageBus] Message bus for communication
      # @param provider [Object] LLM provider instance
      # @param workspace [String, Pathname] Working directory path
      # @param memory_dir [String, Pathname, nil] Directory for memory and session storage (defaults to workspace)
      # @param model [String, nil] Model name to use (defaults to provider default)
      # @param max_iterations [Integer] Maximum tool execution iterations per message
      # @param system_prompt [String, nil] Custom system prompt (defaults to auto-generated)
      # @param mcp_endpoint [String, nil] MCP server endpoint URL (currently unused)
      # @param enable_compaction [Boolean] Whether to enable context compaction
      # @param compaction_threshold [Integer, nil] Message count threshold for compaction
      # @param compaction_model [String, nil] Model to use for compaction summaries (defaults to main model)
      # @param compaction_pressure [Float, nil] Context pressure threshold for compaction (0.0-1.0)
      def initialize(
        bus:,
        provider:,
        workspace:,
        memory_dir: nil,
        model: nil,
        max_iterations: 50,
        system_prompt: nil,
        mcp_endpoint: nil,
        enable_compaction: true,
        compaction_threshold: nil,
        compaction_model: nil,
        compaction_pressure: nil
      )
        @bus = bus
        @provider = provider
        @workspace = Pathname.new(workspace)
        @memory_dir = Pathname.new(memory_dir || workspace)
        @model = model || provider.default_model
        @max_iterations = max_iterations

        @sessions = Session::Manager.new(storage_dir: @memory_dir.join(".pocketrb", "sessions"))

        # Initialize simple memory system
        @memory = Memory.new(workspace: @memory_dir)

        @context = Context.new(
          workspace: @memory_dir,
          system_prompt: system_prompt
        )

        @tools = Tools::Registry.new(workspace: @workspace, memory_dir: @memory_dir, bus: @bus)
        @tools.register_defaults!

        # Pass memory instance to tools
        @tools.update_context(memory: @memory)

        # Load always-on skills into context
        @skills_loader = Skills::Loader.new(workspace: @memory_dir)
        load_always_skills!

        # Initialize context compaction
        @compaction = if enable_compaction
                        Compaction.new(
                          provider: @provider,
                          model: compaction_model || @model,
                          message_threshold: compaction_threshold,
                          context_window: @provider.context_window(model: @model),
                          context_pressure: compaction_pressure
                        )
                      end

        @running = false
      end

      # Start the agent loop (async)
      def run
        @running = true
        Pocketrb.logger.info("Agent loop starting with model: #{@model}")

        Async do
          while @running
            begin
              msg = @bus.consume_inbound
              response = process_message(msg)
              @bus.publish_outbound(response) if response
            rescue StandardError => e
              Pocketrb.logger.error("Error processing message: #{e.message}")
              Pocketrb.logger.error(e.backtrace.first(5).join("\n"))
            end
          end
        end
      end

      # Stop the agent loop
      def stop
        @running = false
        @compaction&.wait_for_compaction(timeout: 10)
        Pocketrb.logger.info("Agent loop stopping")
      end

      # Process a single message (synchronous, for direct use)
      # @param msg [Bus::InboundMessage]
      # @return [Bus::OutboundMessage, nil]
      def process_message(msg)
        # Update tools context with current channel info for message/send_file tools
        @tools.update_context(
          default_channel: msg.channel,
          default_chat_id: msg.chat_id
        )

        session = @sessions.get_or_create(msg.session_key)
        session.add_user_message(msg.content, media: msg.media)

        publish_state_change(msg.session_key, :idle, :processing)

        # Compact session history if needed (before building messages)
        if @compaction&.needs_compaction?(session.messages)
          @compaction.schedule_compaction(session)

          # Wait for compaction to finish; fall back to synchronous if timeout
          unless @compaction.wait_for_compaction(timeout: 30)
            Pocketrb.logger.warn("Background compaction timed out, falling back to synchronous")
            @compaction.compact_session!(session)
          end

          @sessions.save(session)
        end

        # Get relevant memory context for this message
        memory_context = @memory.relevant_context(msg.content, max_facts: 10)

        # Build initial messages (with media support)
        messages = @context.build_messages(
          history: session.get_history(max_messages: 50),
          current: msg.content,
          media: msg.media,
          memory_context: memory_context
        )

        # Drop the last message since we already added it to history
        messages = messages[0..-2] + [session.last_message]

        iteration = 0
        final_response = nil

        while iteration < @max_iterations
          iteration += 1
          Pocketrb.logger.debug("Iteration #{iteration}/#{@max_iterations}")

          response = @provider.chat(
            messages: messages,
            tools: @tools.definitions,
            model: @model
          )

          if response.has_tool_calls?
            messages = execute_tool_calls(session, messages, response)
          else
            final_response = response
            break
          end
        end

        if final_response.nil?
          Pocketrb.logger.warn("Max iterations reached without completion")
          final_response = Providers::LLMResponse.new(
            content: "I apologize, but I've reached the maximum number of iterations. Please try breaking down your request into smaller steps."
          )
        end

        # Save assistant response to session
        session.add_assistant_message(final_response.content, tool_calls: final_response.tool_calls)
        @sessions.save(session)

        publish_state_change(msg.session_key, :processing, :idle)

        # Build outbound message
        Bus::OutboundMessage.new(
          channel: msg.channel,
          chat_id: msg.chat_id,
          content: final_response.content || "",
          reply_to: msg.metadata[:message_id]
        )
      end

      # Register an additional tool
      # @param tool [Tools::Base] Tool instance to add to the registry
      # @return [void]
      def register_tool(tool)
        @tools.register(tool)
      end

      # Update the system prompt
      # @param prompt [String] New system prompt to use for subsequent messages
      # @return [void]
      def update_system_prompt(prompt)
        @context.update_system_prompt(prompt)
      end

      private

      # Execute all tool calls from an LLM response and append results to the message list
      # @param session [Session::Session] active session to persist tool results into
      # @param messages [Array<Message>] current message list to extend with assistant and tool messages
      # @param response [Providers::LLMResponse] LLM response containing tool calls to execute
      # @return [Array<Message>] updated messages with tool call results appended
      def execute_tool_calls(session, messages, response)
        # Add assistant message with tool calls
        assistant_msg = Providers::Message.assistant(
          response.content || "",
          tool_calls: response.tool_calls
        )
        messages << assistant_msg
        session.add_assistant_message(response.content, tool_calls: response.tool_calls)

        # Execute each tool call
        response.tool_calls.each do |tool_call|
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          begin
            result = @tools.execute(tool_call.name, tool_call.arguments)
            duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).to_i

            publish_tool_event(tool_call, result, nil, duration_ms)

            # Add tool result to messages
            tool_msg = Providers::Message.tool_result(
              tool_call_id: tool_call.id,
              name: tool_call.name,
              content: result
            )
            messages << tool_msg
            session.add_tool_result(
              tool_call_id: tool_call.id,
              name: tool_call.name,
              content: result
            )
          rescue ToolError => e
            duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).to_i
            error_msg = "Tool error: #{e.message}"

            publish_tool_event(tool_call, nil, e.message, duration_ms)

            tool_msg = Providers::Message.tool_result(
              tool_call_id: tool_call.id,
              name: tool_call.name,
              content: error_msg
            )
            messages << tool_msg
            session.add_tool_result(
              tool_call_id: tool_call.id,
              name: tool_call.name,
              content: error_msg
            )
          end
        end

        @sessions.save(session)
        messages
      end

      # Publish a tool execution event to the message bus
      # @param tool_call [Providers::ToolCall] the tool call that was executed
      # @param result [String, nil] successful execution output, nil on failure
      # @param error [String, nil] error message if execution failed, nil on success
      # @param duration_ms [Integer] wall-clock execution time in milliseconds
      # @return [void]
      def publish_tool_event(tool_call, result, error, duration_ms)
        event = Bus::ToolExecution.new(
          tool_call_id: tool_call.id,
          name: tool_call.name,
          arguments: tool_call.arguments,
          result: result,
          error: error,
          duration_ms: duration_ms
        )
        @bus.publish_tool_event(event)
      end

      # Publish a session state transition event to the message bus
      # @param session_key [String] identifier of the session changing state
      # @param from [Symbol] previous state (e.g. :idle, :processing)
      # @param to [Symbol] new state being transitioned to
      # @param reason [String, nil] optional explanation for the state change
      # @return [void]
      def publish_state_change(session_key, from, to, reason = nil)
        event = Bus::StateChange.new(
          session_key: session_key,
          from_state: from,
          to_state: to,
          reason: reason
        )
        @bus.publish_state_event(event)
      end

      # Load skills marked as always: true into the system prompt
      def load_always_skills!
        always_skills = @skills_loader.get_always_skills
        return if always_skills.empty?

        skill_content = always_skills.map(&:to_prompt).join("\n\n")
        @context.append_to_system_prompt(skill_content)

        Pocketrb.logger.debug("Loaded #{always_skills.size} always-on skills: #{always_skills.map(&:name).join(", ")}")
      end

      # Load skills triggered by a message (for context-aware skill loading)
      # @param text [String] user message text to match against skill trigger patterns
      # @return [String] concatenated prompt content from matched skills, empty if none match
      def load_triggered_skills(text)
        triggered = @skills_loader.get_triggered_skills(text)
        return "" if triggered.empty?

        triggered.map(&:to_prompt).join("\n\n")
      end
    end
  end
end
