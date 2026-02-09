# frozen_string_literal: true

RSpec.describe Pocketrb::Agent::Compaction do
  let(:provider) { instance_double(Pocketrb::Providers::Base) }
  let(:compaction) do
    described_class.new(
      provider: provider,
      message_threshold: 10, # Lower threshold to trigger compaction easily
      keep_recent: 5 # Keep only 5 recent messages
    )
  end

  before do
    # Mock the summarization call
    response = instance_double(
      Pocketrb::Providers::LLMResponse,
      content: "Summary of earlier conversation"
    )
    allow(provider).to receive_messages(
      default_model: "test-model",
      chat: response
    )
    allow(Pocketrb.logger).to receive(:info)
    allow(Pocketrb.logger).to receive(:error)
  end

  describe "#compact with tool_use/tool_result pairs" do
    let(:messages_with_tool_at_boundary) do
      messages = []
      5.times do |i|
        messages << Pocketrb::Providers::Message.user("Question #{i}")
        messages << Pocketrb::Providers::Message.assistant("Answer #{i}")
      end

      tool_call = Pocketrb::Providers::ToolCall.new(
        id: "toolu_weather",
        name: "get_weather",
        arguments: { location: "SF" }
      )
      messages << Pocketrb::Providers::Message.assistant(nil, tool_calls: [tool_call])
      messages << Pocketrb::Providers::Message.tool_result(
        tool_call_id: "toolu_weather",
        name: "get_weather",
        content: "72F"
      )

      3.times do |i|
        messages << Pocketrb::Providers::Message.user("Recent #{i}")
        messages << Pocketrb::Providers::Message.assistant("Response #{i}")
      end
      messages
    end

    it "keeps tool_use and tool_result together at boundary" do
      compacted = compaction.compact(messages_with_tool_at_boundary)
      kept_messages = compacted[1..]
      tool_result = kept_messages.find { |m| m.role == Pocketrb::Providers::Role::TOOL }

      next unless tool_result

      assistant_with_tools = kept_messages.find do |m|
        m.role == Pocketrb::Providers::Role::ASSISTANT &&
          m.tool_calls&.any? { |tc| tc.id == tool_result.tool_call_id }
      end

      expect(assistant_with_tools).not_to be_nil
    end

    it "prevents Anthropic API error from issue #2" do
      messages = []
      20.times do |i|
        messages << Pocketrb::Providers::Message.user("Query #{i}")
        messages << Pocketrb::Providers::Message.assistant("Response #{i}")
      end

      tool_call = Pocketrb::Providers::ToolCall.new(
        id: "toolu_extract",
        name: "extract_subsystem",
        arguments: { subsystem: "memory" }
      )
      messages << Pocketrb::Providers::Message.assistant(nil, tool_calls: [tool_call])
      messages << Pocketrb::Providers::Message.tool_result(
        tool_call_id: "toolu_extract",
        name: "extract_subsystem",
        content: "Done"
      )

      compacted = compaction.compact(messages)
      tool_results = compacted.select { |m| m.role == Pocketrb::Providers::Role::TOOL }

      tool_results.each do |tool_result|
        has_match = compacted.any? do |m|
          m.role == Pocketrb::Providers::Role::ASSISTANT &&
            m.tool_calls&.any? { |tc| tc.id == tool_result.tool_call_id }
        end
        expect(has_match).to be true
      end
    end
  end

  describe "multiple tool pairs" do
    it "keeps all tool_use/tool_result pairs together" do
      messages = []
      15.times { |i| messages << Pocketrb::Providers::Message.user("Q#{i}") }

      [%w[tool_1 search], %w[tool_2 read_file]].each do |id, name|
        tool_calls = [Pocketrb::Providers::ToolCall.new(id: id, name: name, arguments: {})]
        messages << Pocketrb::Providers::Message.assistant(nil, tool_calls: tool_calls)
        messages << Pocketrb::Providers::Message.tool_result(tool_call_id: id, name: name, content: "result")
      end

      compacted = compaction.compact(messages)
      orphaned = compacted.select { |m| m.role == Pocketrb::Providers::Role::TOOL }.count do |tr|
        compacted.none? { |m| m.role == Pocketrb::Providers::Role::ASSISTANT && m.tool_calls&.any? { |tc| tc.id == tr.tool_call_id } }
      end

      expect(orphaned).to eq(0)
    end
  end

  describe "boundary straddling" do
    it "adjusts split point to keep pairs together" do
      messages = []
      18.times do |i|
        messages << Pocketrb::Providers::Message.user("Message #{i}")
        messages << Pocketrb::Providers::Message.assistant("Response #{i}")
      end

      tool_call = Pocketrb::Providers::ToolCall.new(id: "toolu_test", name: "test_tool", arguments: {})
      messages << Pocketrb::Providers::Message.assistant(nil, tool_calls: [tool_call])
      messages << Pocketrb::Providers::Message.tool_result(tool_call_id: "toolu_test", name: "test_tool", content: "Result")

      2.times do |i|
        messages << Pocketrb::Providers::Message.user("Final #{i}")
        messages << Pocketrb::Providers::Message.assistant("Final #{i}")
      end

      compacted = compaction.compact(messages)
      tool_results = compacted.select { |m| m.role == Pocketrb::Providers::Role::TOOL }

      tool_results.each do |tool_result|
        has_match = compacted.any? do |m|
          m.role == Pocketrb::Providers::Role::ASSISTANT && m.tool_calls&.any? { |tc| tc.id == tool_result.tool_call_id }
        end
        expect(has_match).to be true
      end
    end
  end
end
