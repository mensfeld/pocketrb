# frozen_string_literal: true

RSpec.describe Pocketrb::Bus do
  describe "InboundMessage" do
    let(:message) do
      described_class::InboundMessage.new(
        channel: :telegram,
        sender_id: "user123",
        chat_id: "chat456",
        content: "Hello world",
        media: [],
        metadata: { thread_id: "789" }
      )
    end

    describe "#initialize" do
      it "creates message with required fields" do
        expect(message.channel).to eq(:telegram)
        expect(message.sender_id).to eq("user123")
        expect(message.chat_id).to eq("chat456")
        expect(message.content).to eq("Hello world")
      end

      it "defaults media to empty array" do
        msg = described_class::InboundMessage.new(
          channel: :cli,
          sender_id: "user",
          chat_id: "chat",
          content: "test"
        )

        expect(msg.media).to eq([])
      end

      it "defaults metadata to empty hash" do
        msg = described_class::InboundMessage.new(
          channel: :cli,
          sender_id: "user",
          chat_id: "chat",
          content: "test"
        )

        expect(msg.metadata).to eq({})
      end
    end

    describe "#session_key" do
      it "combines channel and chat_id" do
        expect(message.session_key).to eq("telegram:chat456")
      end

      it "generates unique keys for different channels" do
        msg1 = described_class::InboundMessage.new(
          channel: :telegram,
          sender_id: "user",
          chat_id: "123",
          content: "test"
        )

        msg2 = described_class::InboundMessage.new(
          channel: :discord,
          sender_id: "user",
          chat_id: "123",
          content: "test"
        )

        expect(msg1.session_key).not_to eq(msg2.session_key)
      end
    end

    describe "#has_media?" do
      it "returns false when media is empty" do
        expect(message.has_media?).to be false
      end

      it "returns true when media is present" do
        media = [
          described_class::Media.new(
            type: :image,
            path: "/path/to/image.png",
            mime_type: "image/png"
          )
        ]

        msg = described_class::InboundMessage.new(
          channel: :telegram,
          sender_id: "user",
          chat_id: "chat",
          content: "test",
          media: media
        )

        expect(msg.has_media?).to be true
      end

      it "returns false when media is nil" do
        msg = described_class::InboundMessage.new(
          channel: :telegram,
          sender_id: "user",
          chat_id: "chat",
          content: "test",
          media: nil
        )

        expect(msg).not_to have_media
      end
    end
  end

  describe "OutboundMessage" do
    let(:message) do
      described_class::OutboundMessage.new(
        channel: :telegram,
        chat_id: "chat456",
        content: "Response message"
      )
    end

    describe "#initialize" do
      it "creates message with required fields" do
        expect(message.channel).to eq(:telegram)
        expect(message.chat_id).to eq("chat456")
        expect(message.content).to eq("Response message")
      end

      it "defaults media to empty array" do
        expect(message.media).to eq([])
      end

      it "defaults reply_to to nil" do
        expect(message.reply_to).to be_nil
      end

      it "defaults metadata to empty hash" do
        expect(message.metadata).to eq({})
      end

      it "accepts optional reply_to" do
        msg = described_class::OutboundMessage.new(
          channel: :telegram,
          chat_id: "chat",
          content: "test",
          reply_to: "msg123"
        )

        expect(msg.reply_to).to eq("msg123")
      end
    end
  end

  describe "Media" do
    let(:media) do
      described_class::Media.new(
        type: :image,
        path: "/path/to/image.png",
        mime_type: "image/png",
        filename: "image.png"
      )
    end

    describe "#initialize" do
      it "creates media with required fields" do
        expect(media.type).to eq(:image)
        expect(media.path).to eq("/path/to/image.png")
        expect(media.mime_type).to eq("image/png")
      end

      it "defaults filename to nil" do
        m = described_class::Media.new(
          type: :file,
          path: "/path",
          mime_type: "text/plain"
        )

        expect(m.filename).to be_nil
      end

      it "defaults data to nil" do
        expect(media.data).to be_nil
      end

      it "accepts optional data" do
        m = described_class::Media.new(
          type: :image,
          path: "/path",
          mime_type: "image/png",
          data: "base64data"
        )

        expect(m.data).to eq("base64data")
      end
    end

    describe "#image?" do
      it "returns true for image type" do
        expect(media.image?).to be true
      end

      it "returns false for other types" do
        m = described_class::Media.new(
          type: :file,
          path: "/path",
          mime_type: "text/plain"
        )

        expect(m.image?).to be false
      end
    end

    describe "#file?" do
      it "returns true for file type" do
        m = described_class::Media.new(
          type: :file,
          path: "/path",
          mime_type: "text/plain"
        )

        expect(m.file?).to be true
      end

      it "returns false for other types" do
        expect(media.file?).to be false
      end
    end
  end

  describe "ToolExecution" do
    let(:successful_execution) do
      described_class::ToolExecution.new(
        tool_call_id: "call_123",
        name: "read_file",
        arguments: { path: "test.txt" },
        result: "File contents",
        duration_ms: 50
      )
    end

    let(:failed_execution) do
      described_class::ToolExecution.new(
        tool_call_id: "call_456",
        name: "write_file",
        arguments: { path: "test.txt", content: "data" },
        error: "Permission denied"
      )
    end

    describe "#initialize" do
      it "creates execution with required fields" do
        expect(successful_execution.tool_call_id).to eq("call_123")
        expect(successful_execution.name).to eq("read_file")
        expect(successful_execution.arguments).to eq({ path: "test.txt" })
      end

      it "defaults result to nil" do
        exec = described_class::ToolExecution.new(
          tool_call_id: "call",
          name: "tool",
          arguments: {}
        )

        expect(exec.result).to be_nil
      end

      it "defaults error to nil" do
        expect(successful_execution.error).to be_nil
      end

      it "defaults duration_ms to nil" do
        exec = described_class::ToolExecution.new(
          tool_call_id: "call",
          name: "tool",
          arguments: {}
        )

        expect(exec.duration_ms).to be_nil
      end
    end

    describe "#success?" do
      it "returns true when error is nil" do
        expect(successful_execution.success?).to be true
      end

      it "returns false when error is present" do
        expect(failed_execution.success?).to be false
      end
    end

    describe "#failed?" do
      it "returns false when error is nil" do
        expect(successful_execution.failed?).to be false
      end

      it "returns true when error is present" do
        expect(failed_execution.failed?).to be true
      end
    end
  end

  describe "StateChange" do
    let(:state_change) do
      described_class::StateChange.new(
        session_key: "telegram:123",
        from_state: :idle,
        to_state: :processing,
        reason: "New message received"
      )
    end

    describe "#initialize" do
      it "creates state change with required fields" do
        expect(state_change.session_key).to eq("telegram:123")
        expect(state_change.from_state).to eq(:idle)
        expect(state_change.to_state).to eq(:processing)
      end

      it "defaults reason to nil" do
        sc = described_class::StateChange.new(
          session_key: "cli:456",
          from_state: :idle,
          to_state: :done
        )

        expect(sc.reason).to be_nil
      end

      it "accepts optional reason" do
        expect(state_change.reason).to eq("New message received")
      end
    end
  end
end
