# frozen_string_literal: true

RSpec.describe Pocketrb::Session::Session do
  subject(:session) { described_class.new(key: "test:chat") }

  describe "#add_user_message" do
    it "adds a user message" do
      session.add_user_message("Hello")

      expect(session.message_count).to eq(1)
      expect(session.last_message.role).to eq(Pocketrb::Providers::Role::USER)
      expect(session.last_message.content).to eq("Hello")
    end
  end

  describe "#add_assistant_message" do
    it "adds an assistant message" do
      session.add_assistant_message("Hi there!")

      expect(session.message_count).to eq(1)
      expect(session.last_message.role).to eq(Pocketrb::Providers::Role::ASSISTANT)
    end

    it "supports tool calls" do
      tool_call = Pocketrb::Providers::ToolCall.new(
        id: "tc1",
        name: "read_file",
        arguments: { path: "test.txt" }
      )

      session.add_assistant_message("Let me read that", tool_calls: [tool_call])

      expect(session.last_message.tool_calls).to eq([tool_call])
    end
  end

  describe "#add_tool_result" do
    it "adds a tool result message" do
      session.add_tool_result(
        tool_call_id: "tc1",
        name: "read_file",
        content: "file contents"
      )

      expect(session.last_message.role).to eq(Pocketrb::Providers::Role::TOOL)
      expect(session.last_message.tool_call_id).to eq("tc1")
    end
  end

  describe "#get_history" do
    before do
      3.times { |i| session.add_user_message("Message #{i}") }
    end

    it "returns all messages" do
      expect(session.get_history.length).to eq(3)
    end

    it "supports max_messages limit" do
      history = session.get_history(max_messages: 2)
      expect(history.length).to eq(2)
      expect(history.first.content).to eq("Message 1")
    end
  end

  describe "#clear" do
    it "removes all messages" do
      session.add_user_message("Hello")
      session.clear

      expect(session.empty?).to be true
    end
  end

  describe "#session_key" do
    it "is accessible via key attribute" do
      expect(session.key).to eq("test:chat")
    end
  end

  describe "#to_h / .from_h" do
    it "serializes and deserializes" do
      session.add_user_message("Hello")
      session.add_assistant_message("Hi!")

      hash = session.to_h
      restored = described_class.from_h(hash)

      expect(restored.key).to eq(session.key)
      expect(restored.message_count).to eq(2)
    end
  end
end
