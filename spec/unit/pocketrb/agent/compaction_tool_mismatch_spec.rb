# frozen_string_literal: true

RSpec.describe Pocketrb::Agent::Compaction, "tool_use/tool_result mismatch" do
  let(:provider) { instance_double(Pocketrb::Providers::Base) }
  let(:compaction) do
    described_class.new(
      provider: provider,
      message_threshold: 10,  # Lower threshold to trigger compaction easily
      keep_recent: 5          # Keep only 5 recent messages
    )
  end

  before do
    allow(provider).to receive(:default_model).and_return("test-model")

    # Mock the summarization call
    response = instance_double(
      Pocketrb::Providers::LLMResponse,
      content: "Summary of earlier conversation"
    )
    allow(provider).to receive(:chat).and_return(response)
    allow(Pocketrb.logger).to receive(:info)
    allow(Pocketrb.logger).to receive(:error)
  end

  describe "when tool_use and tool_result are split across compaction boundary" do
    # This test demonstrates the bug reported in issue #2
    # When compaction happens and the assistant message with tool_calls is in the
    # "to_summarize" set, but the tool result message is in the "to_keep" set,
    # the Anthropic API will reject the request because tool_result blocks need
    # matching tool_use blocks in the previous message.
    it "keeps tool_use and tool_result together even at boundary" do
      # Create a conversation that will trigger compaction
      messages = []

      # Add initial user messages (these will be summarized)
      5.times do |i|
        messages << Pocketrb::Providers::Message.user("Question #{i}")
        messages << Pocketrb::Providers::Message.assistant("Answer #{i}")
      end

      # Add an assistant message with a tool call (this will be at the boundary)
      tool_call = Pocketrb::Providers::ToolCall.new(
        id: "toolu_01FycxRcNutGV16ERowZJShS",
        name: "get_weather",
        arguments: { location: "San Francisco" }
      )
      messages << Pocketrb::Providers::Message.assistant(
        nil,
        tool_calls: [tool_call]
      )

      # Add the tool result (this should be in the kept messages)
      messages << Pocketrb::Providers::Message.tool_result(
        tool_call_id: "toolu_01FycxRcNutGV16ERowZJShS",
        name: "get_weather",
        content: "Temperature: 72F"
      )

      # Add a few more recent messages (these will definitely be kept)
      3.times do |i|
        messages << Pocketrb::Providers::Message.user("Recent question #{i}")
        messages << Pocketrb::Providers::Message.assistant("Recent answer #{i}")
      end

      # Verify we need compaction
      expect(compaction.needs_compaction?(messages)).to be true
      expect(messages.size).to eq(18)  # 10 user+assistant + 1 assistant (tool_use) + 1 tool + 6 recent

      # Perform compaction
      compacted = compaction.compact(messages)

      # Compacted should have: 1 summary + kept messages
      expect(compacted.size).to be > 0

      # The kept messages should include the tool pair
      kept_messages = compacted[1..] # Skip summary message

      # Find tool result in kept messages
      tool_result = kept_messages.find { |m| m.role == Pocketrb::Providers::Role::TOOL }

      # Verify the fix: the tool_result should have its matching tool_use
      if tool_result
        assistant_with_tools = kept_messages.find do |m|
          m.role == Pocketrb::Providers::Role::ASSISTANT &&
            m.tool_calls&.any? { |tc| tc.id == tool_result.tool_call_id }
        end

        # With the fix, the assistant message should be present
        expect(assistant_with_tools).not_to be_nil
      end
    end

    it "prevents the Anthropic API error from issue #2" do
      # Recreate the scenario from issue #2
      messages = []

      # Simulate many messages being exchanged
      20.times do |i|
        messages << Pocketrb::Providers::Message.user("Query #{i}")
        messages << Pocketrb::Providers::Message.assistant("Response #{i}")
      end

      # Add tool interaction near the boundary
      tool_call = Pocketrb::Providers::ToolCall.new(
        id: "toolu_extract_memory",
        name: "extract_subsystem",
        arguments: { subsystem: "memory", target_dir: "simple_memory" }
      )
      messages << Pocketrb::Providers::Message.assistant(nil, tool_calls: [tool_call])
      messages << Pocketrb::Providers::Message.tool_result(
        tool_call_id: "toolu_extract_memory",
        name: "extract_subsystem",
        content: "Extracted memory subsystem"
      )

      # Add more recent exchanges
      3.times do |i|
        messages << Pocketrb::Providers::Message.user("Follow-up #{i}")
        messages << Pocketrb::Providers::Message.assistant("Follow-up response #{i}")
      end

      initial_count = messages.size
      expect(compaction.needs_compaction?(messages)).to be true

      # Compact
      compacted = compaction.compact(messages)

      expect(compacted.size).to be < initial_count
      expect(Pocketrb.logger).to have_received(:info).with(/Compacting/)

      # With the fix, sending to Anthropic should succeed because
      # all tool_result blocks have matching tool_use blocks

      # Verify no orphaned tool_results
      tool_results = compacted.select { |m| m.role == Pocketrb::Providers::Role::TOOL }
      tool_results.each do |tool_result|
        # Find if there's a matching assistant message with this tool_call_id
        has_matching_tool_use = compacted.any? do |m|
          m.role == Pocketrb::Providers::Role::ASSISTANT &&
            m.tool_calls&.any? { |tc| tc.id == tool_result.tool_call_id }
        end

        # With the fix, all tool_results should have matching tool_uses
        expect(has_matching_tool_use).to be true
      end
    end
  end

  describe "edge cases with multiple tool calls" do
    it "keeps multiple tool_use/tool_result pairs together" do
      messages = []

      # Build up conversation
      15.times do |i|
        messages << Pocketrb::Providers::Message.user("Q#{i}")
        messages << Pocketrb::Providers::Message.assistant("A#{i}")
      end

      # Add multiple tool interactions that straddle the boundary
      tool_calls_1 = [
        Pocketrb::Providers::ToolCall.new(
          id: "tool_1",
          name: "search",
          arguments: { query: "foo" }
        )
      ]
      messages << Pocketrb::Providers::Message.assistant(nil, tool_calls: tool_calls_1)
      messages << Pocketrb::Providers::Message.tool_result(
        tool_call_id: "tool_1",
        name: "search",
        content: "Results for foo"
      )

      tool_calls_2 = [
        Pocketrb::Providers::ToolCall.new(
          id: "tool_2",
          name: "read_file",
          arguments: { path: "test.rb" }
        )
      ]
      messages << Pocketrb::Providers::Message.assistant("Let me check that file", tool_calls: tool_calls_2)
      messages << Pocketrb::Providers::Message.tool_result(
        tool_call_id: "tool_2",
        name: "read_file",
        content: "File contents"
      )

      # Recent messages
      2.times do |i|
        messages << Pocketrb::Providers::Message.user("Recent #{i}")
        messages << Pocketrb::Providers::Message.assistant("Recent response #{i}")
      end

      compacted = compaction.compact(messages)

      # Verify no orphaned tool results
      orphaned_count = 0
      compacted.select { |m| m.role == Pocketrb::Providers::Role::TOOL }.each do |tool_result|
        has_match = compacted.any? do |m|
          m.role == Pocketrb::Providers::Role::ASSISTANT &&
            m.tool_calls&.any? { |tc| tc.id == tool_result.tool_call_id }
        end
        orphaned_count += 1 unless has_match
      end

      # With the fix, we expect NO orphaned tool results
      expect(orphaned_count).to eq(0)
    end
  end

  describe "fix validation" do
    # This test verifies that tool_use/tool_result pairs are kept together
    # during compaction, even when they straddle the boundary
    it "keeps tool_use/tool_result pairs together across compaction boundary" do
      messages = []

      # Build conversation that needs compaction
      # With keep_recent=5, messages at index 0-36 will be summarized, 37-41 will be kept
      18.times do |i|
        messages << Pocketrb::Providers::Message.user("Message #{i}")
        messages << Pocketrb::Providers::Message.assistant("Response #{i}")
      end

      # Add tool interaction AT THE BOUNDARY
      # This tool_use will be at index 36 (gets summarized)
      tool_call = Pocketrb::Providers::ToolCall.new(
        id: "toolu_test",
        name: "test_tool",
        arguments: {}
      )
      messages << Pocketrb::Providers::Message.assistant(nil, tool_calls: [tool_call])

      # This tool_result will be at index 37 (gets kept)
      messages << Pocketrb::Providers::Message.tool_result(
        tool_call_id: "toolu_test",
        name: "test_tool",
        content: "Result"
      )

      # Add a couple more to ensure we're above keep_recent
      2.times do |i|
        messages << Pocketrb::Providers::Message.user("Final #{i}")
        messages << Pocketrb::Providers::Message.assistant("Final response #{i}")
      end

      compacted = compaction.compact(messages)

      # EXPECTED: All tool results should have matching tool uses
      tool_results = compacted.select { |m| m.role == Pocketrb::Providers::Role::TOOL }

      tool_results.each do |tool_result|
        has_matching_tool_use = compacted.any? do |m|
          m.role == Pocketrb::Providers::Role::ASSISTANT &&
            m.tool_calls&.any? { |tc| tc.id == tool_result.tool_call_id }
        end

        # With the fix, this should pass
        expect(has_matching_tool_use).to be(true),
          "Expected tool_result #{tool_result.tool_call_id} to have matching tool_use in compacted messages"
      end
    end
  end
end
