# frozen_string_literal: true

RSpec.describe Pocketrb::Bus::MessageBus do
  subject(:bus) { described_class.new }

  describe "#publish_inbound / #consume_inbound" do
    it "queues and dequeues inbound messages" do
      message = Pocketrb::Bus::InboundMessage.new(
        channel: :cli,
        sender_id: "user1",
        chat_id: "chat1",
        content: "Hello"
      )

      Async do
        bus.publish_inbound(message)
        received = bus.consume_inbound
        expect(received).to eq(message)
      end
    end

    it "raises on invalid message type" do
      expect { bus.publish_inbound("not a message") }.to raise_error(ArgumentError)
    end
  end

  describe "#publish_outbound / #consume_outbound" do
    it "queues and dequeues outbound messages" do
      message = Pocketrb::Bus::OutboundMessage.new(
        channel: :cli,
        chat_id: "chat1",
        content: "Response"
      )

      Async do
        bus.publish_outbound(message)
        received = bus.consume_outbound
        expect(received).to eq(message)
      end
    end
  end

  describe "#subscribe" do
    it "notifies subscribers of inbound messages" do
      received_messages = []

      bus.subscribe(:inbound) { |msg| received_messages << msg }

      message = Pocketrb::Bus::InboundMessage.new(
        channel: :cli,
        sender_id: "user1",
        chat_id: "chat1",
        content: "Test"
      )

      bus.publish_inbound(message)

      expect(received_messages).to eq([message])
    end

    it "raises on unknown event type" do
      expect { bus.subscribe(:unknown) {} }.to raise_error(ArgumentError)
    end
  end

  describe "#stats" do
    it "tracks message counts" do
      inbound = Pocketrb::Bus::InboundMessage.new(
        channel: :cli,
        sender_id: "user1",
        chat_id: "chat1",
        content: "Hello"
      )

      outbound = Pocketrb::Bus::OutboundMessage.new(
        channel: :cli,
        chat_id: "chat1",
        content: "Response"
      )

      bus.publish_inbound(inbound)
      bus.publish_outbound(outbound)

      expect(bus.stats[:inbound]).to eq(1)
      expect(bus.stats[:outbound]).to eq(1)
    end
  end

  describe "#clear!" do
    it "resets queues and stats" do
      inbound = Pocketrb::Bus::InboundMessage.new(
        channel: :cli,
        sender_id: "user1",
        chat_id: "chat1",
        content: "Hello"
      )

      bus.publish_inbound(inbound)
      bus.clear!

      expect(bus.stats[:inbound]).to eq(0)
      expect(bus.pending_inbound?).to be false
    end
  end
end
