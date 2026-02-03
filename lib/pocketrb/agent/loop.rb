# frozen_string_literal: true

require "async"

module Pocketrb
  module Agent
    # Core agent processing loop
    class Loop
      attr_reader :bus, :provider, :tools, :sessions, :context
      attr_reader :model, :max_iterations, :workspace, :qmd_memory, :compaction

      def initialize(
        bus:,
        provider:,
        workspace:,
        model: nil,
        max_iterations: 50,
        system_prompt: nil,
        mcp_endpoint: nil,
        enable_qmd: true,
        enable_compaction: true,
        compaction_threshold: nil
      )
        @bus = bus
        @provider = provider
        @workspace = Pathname.new(workspace)
        @model = model || provider.default_model
        @max_iterations = max_iterations

        @sessions = Session::Manager.new(storage_dir: @workspace.join(".pocketrb", "sessions"))

        # Initialize QMD memory (combines local memory + QMD vector store)
        @qmd_memory = if enable_qmd
                        Memory::QMD.new(workspace: @workspace, endpoint: mcp_endpoint)
                      end

        @context = Context.new(
          workspace: @workspace,
          system_prompt: system_prompt,
          qmd_memory: @qmd_memory
        )

        @tools = Tools::Registry.new(workspace: @workspace, bus: @bus)
        @tools.register_defaults!

        # Register memory tool with MCP client
        if @qmd_memory
          memory_tool = MCP::MemoryTool.new(
            workspace: @workspace,
            bus: @bus,
            mcp_client: @qmd_memory.client
          )
          @tools.register(memory_tool)
        end

        # Initialize context compaction
        @compaction = if enable_compaction
                        Compaction.new(
                          provider: @provider,
                          model: @model,
                          message_threshold: compaction_threshold
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
        Pocketrb.logger.info("Agent loop stopping")
      end

      # Process a single message (synchronous, for direct use)
      # @param msg [Bus::InboundMessage]
      # @return [Bus::OutboundMessage|nil]
      def process_message(msg)
        session = @sessions.get_or_create(msg.session_key)
        session.add_user_message(msg.content, media: msg.media)

        publish_state_change(msg.session_key, :idle, :processing)

        # Compact session history if needed (before building messages)
        if @compaction && @compaction.needs_compaction?(session.messages)
          @compaction.compact_session!(session)
          @sessions.save(session)
        end

        # Build initial messages (with media support)
        messages = @context.build_messages(
          history: session.get_history(max_messages: 50),
          current: msg.content,
          media: msg.media
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
      def register_tool(tool)
        @tools.register(tool)
      end

      # Update the system prompt
      def update_system_prompt(prompt)
        @context.update_system_prompt(prompt)
      end

      private

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

      def publish_state_change(session_key, from, to, reason = nil)
        event = Bus::StateChange.new(
          session_key: session_key,
          from_state: from,
          to_state: to,
          reason: reason
        )
        @bus.publish_state_event(event)
      end
    end
  end
end
