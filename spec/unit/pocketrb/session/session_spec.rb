# frozen_string_literal: true

RSpec.describe Pocketrb::Session::Session do
  let(:session_key) { "telegram:12345" }
  let(:session) { described_class.new(key: session_key) }

  describe "#initialize" do
    it "stores session key" do
      expect(session.key).to eq(session_key)
    end

    it "initializes empty messages array" do
      expect(session.messages).to eq([])
    end

    it "initializes empty metadata hash" do
      expect(session.metadata).to eq({})
    end

    it "sets created_at timestamp" do
      expect(session.created_at).to be_a(Time)
      expect(session.created_at).to be_within(1).of(Time.now)
    end

    it "accepts initial messages" do
      msg = instance_double(Pocketrb::Providers::Message)
      session = described_class.new(key: "test", messages: [msg])

      expect(session.messages).to eq([msg])
    end

    it "accepts initial metadata" do
      meta = { user: "Alice" }
      session = described_class.new(key: "test", metadata: meta)

      expect(session.metadata).to eq(meta)
    end
  end

  describe "#add_message" do
    it "adds message to session" do
      session.add_message(role: "user", content: "Hello")

      expect(session.message_count).to eq(1)
      expect(session.last_message.role).to eq("user")
      expect(session.last_message.content).to eq("Hello")
    end

    it "accepts additional attributes" do
      session.add_message(
        role: "assistant",
        content: "Response",
        name: "bot",
        tool_calls: []
      )

      msg = session.last_message
      expect(msg.name).to eq("bot")
      expect(msg.tool_calls).to eq([])
    end

    it "is thread-safe" do
      threads = Array.new(10) do
        Thread.new do
          10.times { session.add_message(role: "user", content: "Test") }
        end
      end
      threads.each(&:join)

      expect(session.message_count).to eq(100)
    end
  end

  describe "#add_user_message" do
    it "adds simple text message" do
      session.add_user_message("Hello world")

      msg = session.last_message
      expect(msg.role).to eq(Pocketrb::Providers::Role::USER)
      expect(msg.content).to eq("Hello world")
    end

    it "adds message with media attachments" do
      media = [
        Pocketrb::Bus::Media.new(
          type: :image,
          path: "/tmp/pic.jpg",
          mime_type: "image/jpeg",
          filename: "pic.jpg"
        )
      ]

      session.add_user_message("Check this out", media: media)

      msg = session.last_message
      expect(msg.content).to be_an(Array)
      expect(msg.content[0][:type]).to eq("text")
      expect(msg.content[0][:text]).to eq("Check this out")
      expect(msg.content[1][:type]).to eq("media")
      expect(msg.content[1][:media][:type]).to eq(:image)
      expect(msg.content[1][:media][:path]).to eq("/tmp/pic.jpg")
    end

    it "handles media-only message" do
      media = [
        Pocketrb::Bus::Media.new(
          type: :image,
          path: "/tmp/pic.jpg",
          mime_type: "image/jpeg"
        )
      ]

      session.add_user_message("", media: media)

      msg = session.last_message
      expect(msg.content).to be_an(Array)
      expect(msg.content.length).to eq(1)
      expect(msg.content[0][:type]).to eq("media")
    end

    it "handles empty media array" do
      session.add_user_message("Text only", media: [])

      msg = session.last_message
      expect(msg.content).to eq("Text only")
    end
  end

  describe "#add_assistant_message" do
    it "adds assistant message" do
      session.add_assistant_message("Response")

      msg = session.last_message
      expect(msg.role).to eq(Pocketrb::Providers::Role::ASSISTANT)
      expect(msg.content).to eq("Response")
    end

    it "adds message with tool calls" do
      tool_call = Pocketrb::Providers::ToolCall.new(
        id: "call_123",
        name: "read_file",
        arguments: { path: "/tmp/test.txt" }
      )

      session.add_assistant_message("Let me read that", tool_calls: [tool_call])

      msg = session.last_message
      expect(msg.tool_calls).not_to be_nil
      expect(msg.tool_calls.first.id).to eq("call_123")
      expect(msg.tool_calls.first.name).to eq("read_file")
    end

    it "sanitizes large tool call arguments" do
      large_arg = "x" * 1000
      tool_call = Pocketrb::Providers::ToolCall.new(
        id: "call_123",
        name: "write_file",
        arguments: { content: large_arg }
      )

      session.add_assistant_message("Writing", tool_calls: [tool_call])

      msg = session.last_message
      sanitized = msg.tool_calls.first.arguments[:content]
      expect(sanitized.length).to be < large_arg.length
      expect(sanitized).to include("[truncated")
    end
  end

  describe "#add_tool_result" do
    it "adds tool result message" do
      session.add_tool_result(
        tool_call_id: "call_123",
        name: "read_file",
        content: "File contents"
      )

      msg = session.last_message
      expect(msg.role).to eq(Pocketrb::Providers::Role::TOOL)
      expect(msg.tool_call_id).to eq("call_123")
      expect(msg.name).to eq("read_file")
      expect(msg.content).to eq("File contents")
    end

    it "truncates large tool results" do
      large_result = "x" * 3000

      session.add_tool_result(
        tool_call_id: "call_123",
        name: "bash",
        content: large_result
      )

      msg = session.last_message
      expect(msg.content.length).to be < large_result.length
      expect(msg.content).to include("[truncated 1000 chars]")
    end

    it "preserves small tool results" do
      small_result = "Success"

      session.add_tool_result(
        tool_call_id: "call_123",
        name: "tool",
        content: small_result
      )

      expect(session.last_message.content).to eq(small_result)
    end
  end

  describe "#get_history" do
    before do
      3.times { |i| session.add_message(role: "user", content: "Message #{i}") }
    end

    it "returns all messages by default" do
      history = session.get_history

      expect(history.length).to eq(3)
    end

    it "returns copy of messages array" do
      history = session.get_history
      history << "fake"

      expect(session.message_count).to eq(3)
    end

    it "limits number of messages returned" do
      history = session.get_history(max_messages: 2)

      expect(history.length).to eq(2)
      expect(history.last.content).to eq("Message 2")
    end

    it "returns last N messages" do
      history = session.get_history(max_messages: 1)

      expect(history.first.content).to eq("Message 2")
    end
  end

  describe "#clear" do
    it "removes all messages" do
      session.add_message(role: "user", content: "Test")
      expect(session.message_count).to eq(1)

      session.clear

      expect(session.message_count).to eq(0)
      expect(session.empty?).to be true
    end
  end

  describe "#last_message" do
    it "returns most recent message" do
      session.add_message(role: "user", content: "First")
      session.add_message(role: "user", content: "Second")

      expect(session.last_message.content).to eq("Second")
    end

    it "returns nil for empty session" do
      expect(session.last_message).to be_nil
    end
  end

  describe "#message_count" do
    it "returns zero for new session" do
      expect(session.message_count).to eq(0)
    end

    it "counts messages correctly" do
      3.times { session.add_message(role: "user", content: "Test") }

      expect(session.message_count).to eq(3)
    end
  end

  describe "#empty?" do
    it "returns true for new session" do
      expect(session.empty?).to be true
    end

    it "returns false after adding messages" do
      session.add_message(role: "user", content: "Test")

      expect(session.empty?).to be false
    end

    it "returns true after clearing" do
      session.add_message(role: "user", content: "Test")
      session.clear

      expect(session.empty?).to be true
    end
  end

  describe "#set_meta and #get_meta" do
    it "stores metadata value" do
      session.set_meta(:user, "Alice")

      expect(session.get_meta(:user)).to eq("Alice")
    end

    it "returns nil for missing key" do
      expect(session.get_meta(:nonexistent)).to be_nil
    end

    it "overwrites existing values" do
      session.set_meta(:count, 1)
      session.set_meta(:count, 2)

      expect(session.get_meta(:count)).to eq(2)
    end

    it "is thread-safe" do
      threads = Array.new(10) do |i|
        Thread.new { session.set_meta(:"key_#{i}", i) }
      end
      threads.each(&:join)

      expect(session.metadata.keys.length).to eq(10)
    end
  end

  describe "#to_h" do
    it "serializes session to hash" do
      session.add_message(role: "user", content: "Hello")
      session.set_meta(:user, "Alice")

      hash = session.to_h

      expect(hash[:key]).to eq(session_key)
      expect(hash[:messages].length).to eq(1)
      expect(hash[:metadata]).to eq({ user: "Alice" })
      expect(hash[:created_at]).to be_a(String)
    end

    it "includes ISO8601 timestamp" do
      hash = session.to_h

      expect { Time.parse(hash[:created_at]) }.not_to raise_error
    end
  end

  describe ".from_h" do
    let(:hash) do
      {
        key: "test:123",
        messages: [
          {
            role: "user",
            content: "Hello"
          }
        ],
        metadata: { user: "Bob" },
        created_at: "2024-01-01T10:00:00Z"
      }
    end

    it "restores session from hash" do
      session = described_class.from_h(hash)

      expect(session.key).to eq("test:123")
      expect(session.message_count).to eq(1)
      expect(session.last_message.content).to eq("Hello")
      expect(session.metadata).to eq({ user: "Bob" })
    end

    it "restores timestamp" do
      session = described_class.from_h(hash)

      expect(session.created_at).to eq(Time.parse("2024-01-01T10:00:00Z"))
    end

    it "handles string keys" do
      string_hash = {
        "key" => "test:123",
        "messages" => [],
        "metadata" => {},
        "created_at" => Time.now.iso8601
      }

      session = described_class.from_h(string_hash)

      expect(session.key).to eq("test:123")
    end

    it "handles missing metadata" do
      minimal_hash = {
        key: "test",
        messages: [],
        created_at: Time.now.iso8601
      }

      session = described_class.from_h(minimal_hash)

      expect(session.metadata).to eq({})
    end

    it "returns new session on parse error" do
      invalid_hash = {
        key: "test",
        messages: [],
        created_at: "invalid-date"
      }

      session = described_class.from_h(invalid_hash)

      expect(session.key).to eq("test")
      expect(session.empty?).to be true
    end
  end
end
