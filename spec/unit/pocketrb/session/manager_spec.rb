# frozen_string_literal: true

RSpec.describe Pocketrb::Session::Manager do
  let(:storage_dir) { Pathname.new(Dir.mktmpdir) }
  let(:manager) { described_class.new(storage_dir: storage_dir) }

  after do
    FileUtils.rm_rf(storage_dir)
  end

  describe "#initialize" do
    it "creates storage directory if it doesn't exist" do
      new_dir = storage_dir.join("new_sessions")
      described_class.new(storage_dir: new_dir)

      expect(new_dir).to exist
    end

    it "sets storage_dir" do
      expect(manager.storage_dir).to eq(storage_dir)
    end
  end

  describe "#get_or_create" do
    it "creates new session when it doesn't exist" do
      session = manager.get_or_create("test:123")

      expect(session).to be_a(Pocketrb::Session::Session)
      expect(session.key).to eq("test:123")
      expect(session.messages).to be_empty
    end

    it "returns existing session" do
      session1 = manager.get_or_create("test:123")
      session1.add_message(role: "system", content: "Test")
      manager.save(session1)

      session2 = manager.get_or_create("test:123")

      expect(session2.messages.length).to eq(1)
    end

    it "caches sessions in memory" do
      session1 = manager.get_or_create("test:123")
      session2 = manager.get_or_create("test:123")

      expect(session1).to be(session2)
    end
  end

  describe "#get" do
    it "returns nil for non-existent session" do
      session = manager.get("nonexistent")

      expect(session).to be_nil
    end

    it "returns existing session from memory" do
      created = manager.get_or_create("test:123")
      retrieved = manager.get("test:123")

      expect(retrieved).to be(created)
    end

    it "loads session from disk" do
      session = Pocketrb::Session::Session.new(key: "test:456")
      session.add_message(role: "system", content: "Test")
      manager.save(session)

      # Clear memory cache
      manager.instance_variable_get(:@sessions).clear

      loaded = manager.get("test:456")

      expect(loaded).not_to be_nil
      expect(loaded.messages.length).to eq(1)
    end
  end

  describe "#save" do
    it "saves session to memory" do
      session = Pocketrb::Session::Session.new(key: "test:123")
      manager.save(session)

      retrieved = manager.get("test:123")

      expect(retrieved).to eq(session)
    end

    it "persists session to disk" do
      session = Pocketrb::Session::Session.new(key: "test:789")
      session.add_message(role: "user", content: "Hello")
      manager.save(session)

      file = storage_dir.join("test_789.jsonl")

      expect(file).to exist
    end

    it "sanitizes key for filename" do
      session = Pocketrb::Session::Session.new(key: "telegram:chat/123")
      manager.save(session)

      file = storage_dir.join("telegram_chat_123.jsonl")

      expect(file).to exist
    end
  end

  describe "#delete" do
    it "removes session from memory" do
      manager.get_or_create("test:123")
      manager.delete("test:123")

      expect(manager.get("test:123")).to be_nil
    end

    it "deletes session file from disk" do
      session = Pocketrb::Session::Session.new(key: "test:delete")
      manager.save(session)

      file = storage_dir.join("test_delete.jsonl")
      expect(file).to exist

      manager.delete("test:delete")

      expect(file).not_to exist
    end
  end

  describe "#list_keys" do
    it "returns empty array when no sessions" do
      expect(manager.list_keys).to eq([])
    end

    it "lists sessions in memory" do
      manager.get_or_create("session1")
      manager.get_or_create("session2")

      keys = manager.list_keys

      expect(keys).to include("session1", "session2")
    end

    it "lists sessions on disk" do
      session = Pocketrb::Session::Session.new(key: "persisted")
      manager.save(session)

      # Clear memory
      manager.instance_variable_get(:@sessions).clear

      keys = manager.list_keys

      expect(keys).to include("persisted")
    end

    it "returns unique keys from both memory and disk" do
      manager.get_or_create("memory_only")

      session = Pocketrb::Session::Session.new(key: "disk_only")
      manager.save(session)
      manager.instance_variable_get(:@sessions).delete("disk_only")

      keys = manager.list_keys

      expect(keys).to include("memory_only", "disk_only")
      expect(keys.length).to eq(2)
    end
  end

  describe "#append_message" do
    it "appends message to session file" do
      manager.get_or_create("test:append")
      message = Pocketrb::Providers::Message.user("Appended")

      manager.append_message("test:append", message)

      file = storage_dir.join("test_append.jsonl")
      content = File.read(file)

      expect(content).to include("Appended")
    end

    it "creates file if it doesn't exist" do
      message = Pocketrb::Providers::Message.system("First")

      manager.append_message("new:session", message)

      file = storage_dir.join("new_session.jsonl")

      expect(file).to exist
    end
  end

  describe "#clear_all!" do
    it "clears all sessions from memory" do
      manager.get_or_create("session1")
      manager.get_or_create("session2")

      manager.clear_all!

      expect(manager.get("session1")).to be_nil
      expect(manager.get("session2")).to be_nil
    end

    it "deletes all session files" do
      session1 = Pocketrb::Session::Session.new(key: "file1")
      session2 = Pocketrb::Session::Session.new(key: "file2")
      manager.save(session1)
      manager.save(session2)

      manager.clear_all!

      files = Dir.glob(storage_dir.join("*.jsonl"))

      expect(files).to be_empty
    end
  end

  describe "persistence and loading" do
    it "persists and loads user messages" do
      session = Pocketrb::Session::Session.new(key: "test:user")
      session.add_message(role: "user", content: "User message")
      manager.save(session)

      # Clear cache and reload
      manager.instance_variable_get(:@sessions).clear
      loaded = manager.get("test:user")

      expect(loaded.messages.first.role).to eq(Pocketrb::Providers::Role::USER)
      expect(loaded.messages.first.content).to eq("User message")
    end

    it "persists and loads assistant messages" do
      session = Pocketrb::Session::Session.new(key: "test:assistant")
      session.add_message(role: "assistant", content: "Assistant response")
      manager.save(session)

      manager.instance_variable_get(:@sessions).clear
      loaded = manager.get("test:assistant")

      expect(loaded.messages.first.role).to eq(Pocketrb::Providers::Role::ASSISTANT)
      expect(loaded.messages.first.content).to eq("Assistant response")
    end

    it "persists and loads messages with tool calls" do
      tool_call = Pocketrb::Providers::ToolCall.new(
        id: "call_123",
        name: "read_file",
        arguments: { path: "test.txt" }
      )
      session = Pocketrb::Session::Session.new(key: "test:tools")
      session.add_message(role: "assistant", content: "Using tool", tool_calls: [tool_call])
      manager.save(session)

      manager.instance_variable_get(:@sessions).clear
      loaded = manager.get("test:tools")

      expect(loaded.messages.first.tool_calls.length).to eq(1)
      expect(loaded.messages.first.tool_calls.first.name).to eq("read_file")
    end

    it "persists and loads tool result messages" do
      session = Pocketrb::Session::Session.new(key: "test:result")
      session.add_message(
        role: "tool",
        content: "File contents",
        tool_call_id: "call_123",
        name: "read_file"
      )
      manager.save(session)

      manager.instance_variable_get(:@sessions).clear
      loaded = manager.get("test:result")

      expect(loaded.messages.first.role).to eq(Pocketrb::Providers::Role::TOOL)
      expect(loaded.messages.first.tool_call_id).to eq("call_123")
      expect(loaded.messages.first.content).to eq("File contents")
    end

    it "handles invalid UTF-8 in content" do
      session = Pocketrb::Session::Session.new(key: "test:utf8")
      invalid_string = (+"Test \xFF invalid UTF-8").force_encoding("UTF-8")
      session.add_message(role: "user", content: invalid_string)
      manager.save(session)

      manager.instance_variable_get(:@sessions).clear
      loaded = manager.get("test:utf8")

      expect(loaded.messages.first.content).to be_a(String)
      expect(loaded.messages.first.content.valid_encoding?).to be true
    end

    it "handles corrupted JSONL file" do
      file = storage_dir.join("corrupted.jsonl")
      File.write(file, "invalid json\n{\"role\":\"user\"}\n")

      session = manager.get("corrupted")

      expect(session).not_to be_nil
      expect(session.messages).to be_empty
    end
  end
end
