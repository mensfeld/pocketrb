# frozen_string_literal: true

RSpec.describe Pocketrb::Bus::MessageBus do
  let(:bus) { described_class.new }

  describe "#initialize" do
    it "creates empty stats" do
      expect(bus.stats[:inbound]).to eq(0)
      expect(bus.stats[:outbound]).to eq(0)
      expect(bus.stats[:tool_executions]).to eq(0)
      expect(bus.stats[:state_changes]).to eq(0)
    end
  end

  describe "#publish_inbound" do
    let(:message) do
      Pocketrb::Bus::InboundMessage.new(
        channel: :test,
        sender_id: "user123",
        chat_id: "chat456",
        content: "Hello"
      )
    end

    it "accepts InboundMessage" do
      expect { bus.publish_inbound(message) }.not_to raise_error
    end

    it "increments inbound stats" do
      bus.publish_inbound(message)
      expect(bus.stats[:inbound]).to eq(1)
    end

    it "raises ArgumentError for non-InboundMessage" do
      expect { bus.publish_inbound("not a message") }.to raise_error(ArgumentError, /Expected InboundMessage/)
    end

    it "notifies inbound subscribers" do
      received = nil
      bus.subscribe(:inbound) { |msg| received = msg }

      bus.publish_inbound(message)

      expect(received).to eq(message)
    end
  end

  describe "#consume_inbound" do
    let(:message) do
      Pocketrb::Bus::InboundMessage.new(
        channel: :test,
        sender_id: "user123",
        chat_id: "chat456",
        content: "Hello"
      )
    end

    it "returns published message" do
      bus.publish_inbound(message)

      consumed = nil
      Thread.new { consumed = bus.consume_inbound }.join(1)

      expect(consumed).to eq(message)
    end
  end

  describe "#publish_outbound" do
    let(:message) do
      Pocketrb::Bus::OutboundMessage.new(
        channel: :test,
        chat_id: "chat456",
        content: "Response"
      )
    end

    it "accepts OutboundMessage" do
      expect { bus.publish_outbound(message) }.not_to raise_error
    end

    it "increments outbound stats" do
      bus.publish_outbound(message)
      expect(bus.stats[:outbound]).to eq(1)
    end

    it "raises ArgumentError for non-OutboundMessage" do
      expect { bus.publish_outbound("not a message") }.to raise_error(ArgumentError, /Expected OutboundMessage/)
    end

    it "notifies outbound subscribers" do
      received = nil
      bus.subscribe(:outbound) { |msg| received = msg }

      bus.publish_outbound(message)

      expect(received).to eq(message)
    end
  end

  describe "#consume_outbound" do
    let(:message) do
      Pocketrb::Bus::OutboundMessage.new(
        channel: :test,
        chat_id: "chat456",
        content: "Response"
      )
    end

    it "returns published message" do
      bus.publish_outbound(message)

      consumed = nil
      Thread.new { consumed = bus.consume_outbound }.join(1)

      expect(consumed).to eq(message)
    end
  end

  describe "#publish_tool_event" do
    let(:event) do
      Pocketrb::Bus::ToolExecution.new(
        tool_call_id: "call_123",
        name: "test_tool",
        arguments: { key: "value" }
      )
    end

    it "accepts ToolExecution" do
      expect { bus.publish_tool_event(event) }.not_to raise_error
    end

    it "increments tool_executions stats" do
      bus.publish_tool_event(event)
      expect(bus.stats[:tool_executions]).to eq(1)
    end

    it "raises ArgumentError for non-ToolExecution" do
      expect { bus.publish_tool_event("not an event") }.to raise_error(ArgumentError, /Expected ToolExecution/)
    end

    it "notifies tool subscribers" do
      received = nil
      bus.subscribe(:tool) { |evt| received = evt }

      bus.publish_tool_event(event)

      expect(received).to eq(event)
    end
  end

  describe "#consume_tool_event" do
    let(:event) do
      Pocketrb::Bus::ToolExecution.new(
        tool_call_id: "call_123",
        name: "test_tool",
        arguments: {}
      )
    end

    it "returns published event" do
      bus.publish_tool_event(event)

      consumed = nil
      Thread.new { consumed = bus.consume_tool_event }.join(1)

      expect(consumed).to eq(event)
    end
  end

  describe "#publish_state_event" do
    let(:event) do
      Pocketrb::Bus::StateChange.new(
        session_key: "test:123",
        from_state: :idle,
        to_state: :processing
      )
    end

    it "accepts StateChange" do
      expect { bus.publish_state_event(event) }.not_to raise_error
    end

    it "increments state_changes stats" do
      bus.publish_state_event(event)
      expect(bus.stats[:state_changes]).to eq(1)
    end

    it "raises ArgumentError for non-StateChange" do
      expect { bus.publish_state_event("not an event") }.to raise_error(ArgumentError, /Expected StateChange/)
    end

    it "notifies state subscribers" do
      received = nil
      bus.subscribe(:state) { |evt| received = evt }

      bus.publish_state_event(event)

      expect(received).to eq(event)
    end
  end

  describe "#subscribe" do
    it "accepts valid event type" do
      expect { bus.subscribe(:inbound) { |_| } }.not_to raise_error
    end

    it "raises ArgumentError for unknown type" do
      expect { bus.subscribe(:invalid) { |_| } }.to raise_error(ArgumentError, /Unknown event type/)
    end

    it "allows multiple subscribers" do
      count = 0
      bus.subscribe(:inbound) { count += 1 }
      bus.subscribe(:inbound) { count += 10 }

      message = Pocketrb::Bus::InboundMessage.new(
        channel: :test,
        sender_id: "user",
        chat_id: "chat",
        content: "Test"
      )
      bus.publish_inbound(message)

      expect(count).to eq(11)
    end
  end

  describe "#unsubscribe" do
    it "removes subscriber" do
      received = 0
      handler = proc { received += 1 }

      bus.subscribe(:inbound, &handler)
      bus.unsubscribe(:inbound, handler)

      message = Pocketrb::Bus::InboundMessage.new(
        channel: :test,
        sender_id: "user",
        chat_id: "chat",
        content: "Test"
      )
      bus.publish_inbound(message)

      expect(received).to eq(0)
    end
  end

  describe "#pending_inbound?" do
    it "returns false for empty queue" do
      expect(bus.pending_inbound?).to be false
    end

    it "returns true after publishing" do
      message = Pocketrb::Bus::InboundMessage.new(
        channel: :test,
        sender_id: "user",
        chat_id: "chat",
        content: "Test"
      )
      bus.publish_inbound(message)

      expect(bus.pending_inbound?).to be true
    end
  end

  describe "#pending_outbound?" do
    it "returns false for empty queue" do
      expect(bus.pending_outbound?).to be false
    end

    it "returns true after publishing" do
      message = Pocketrb::Bus::OutboundMessage.new(
        channel: :test,
        chat_id: "chat",
        content: "Test"
      )
      bus.publish_outbound(message)

      expect(bus.pending_outbound?).to be true
    end
  end

  describe "#clear!" do
    before do
      bus.publish_inbound(
        Pocketrb::Bus::InboundMessage.new(
          channel: :test,
          sender_id: "user",
          chat_id: "chat",
          content: "Test"
        )
      )
      bus.publish_outbound(
        Pocketrb::Bus::OutboundMessage.new(
          channel: :test,
          chat_id: "chat",
          content: "Response"
        )
      )
    end

    it "clears all queues" do
      bus.clear!

      expect(bus.pending_inbound?).to be false
      expect(bus.pending_outbound?).to be false
    end

    it "resets stats" do
      bus.clear!

      expect(bus.stats[:inbound]).to eq(0)
      expect(bus.stats[:outbound]).to eq(0)
    end
  end

  describe "Stats" do
    let(:stats) { described_class::Stats.new }

    describe "#initialize" do
      it "starts with zero counts" do
        expect(stats[:inbound]).to eq(0)
        expect(stats[:outbound]).to eq(0)
        expect(stats[:tool_executions]).to eq(0)
        expect(stats[:state_changes]).to eq(0)
      end
    end

    describe "#increment" do
      it "increments specified counter" do
        stats.increment(:inbound)
        expect(stats[:inbound]).to eq(1)
      end

      it "is thread-safe" do
        threads = Array.new(10) do
          Thread.new { 10.times { stats.increment(:inbound) } }
        end
        threads.each(&:join)

        expect(stats[:inbound]).to eq(100)
      end
    end

    describe "#[]" do
      it "returns counter value" do
        stats.increment(:outbound)
        stats.increment(:outbound)

        expect(stats[:outbound]).to eq(2)
      end
    end

    describe "#reset!" do
      it "resets all counters to zero" do
        stats.increment(:inbound)
        stats.increment(:outbound)

        stats.reset!

        expect(stats[:inbound]).to eq(0)
        expect(stats[:outbound]).to eq(0)
      end
    end

    describe "#to_h" do
      it "returns hash of all stats" do
        stats.increment(:inbound)

        hash = stats.to_h

        expect(hash).to be_a(Hash)
        expect(hash[:inbound]).to eq(1)
      end

      it "returns a copy" do
        hash = stats.to_h
        hash[:inbound] = 999

        expect(stats[:inbound]).to eq(0)
      end
    end
  end
end
