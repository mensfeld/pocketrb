# frozen_string_literal: true

# Test implementation of Channel::Base
class TestChannel < Pocketrb::Channels::Base
  attr_reader :sent_messages, :inbound_loop_called

  def initialize(bus:, name: nil)
    super
    @sent_messages = []
    @inbound_loop_called = false
  end

  protected

  def run_inbound_loop
    @inbound_loop_called = true
    # Don't actually loop in tests
  end

  def send_message(message)
    @sent_messages << message
  end
end

RSpec.describe Pocketrb::Channels::Base do
  let(:bus) { instance_double(Pocketrb::Bus::MessageBus) }
  let(:channel) { TestChannel.new(bus: bus) }

  describe "#initialize" do
    it "stores bus" do
      expect(channel.bus).to eq(bus)
    end

    it "sets name from class name" do
      expect(channel.name).to eq(:testchannel)
    end

    it "accepts custom name" do
      custom_channel = TestChannel.new(bus: bus, name: :custom)

      expect(custom_channel.name).to eq(:custom)
    end

    it "starts not running" do
      expect(channel.running?).to be false
    end
  end

  describe "#run" do
    before do
      # Stub the outbound consumer to avoid actually starting the async loop
      allow(channel).to receive(:start_outbound_consumer)
    end

    it "sets running to true" do
      channel.run

      expect(channel.running?).to be true
    end

    it "calls run_inbound_loop" do
      channel.run

      expect(channel.inbound_loop_called).to be true
    end

    it "starts outbound consumer" do
      channel.run

      expect(channel).to have_received(:start_outbound_consumer)
    end
  end

  describe "#stop" do
    it "sets running to false" do
      channel.instance_variable_set(:@running, true)

      channel.stop

      expect(channel.running?).to be false
    end
  end

  describe "#running?" do
    it "returns false initially" do
      expect(channel.running?).to be false
    end

    it "returns true after starting" do
      channel.instance_variable_set(:@running, true)

      expect(channel.running?).to be true
    end

    it "returns false after stopping" do
      channel.instance_variable_set(:@running, true)
      channel.stop

      expect(channel.running?).to be false
    end
  end

  describe "#send_message" do
    it "raises NotImplementedError for base class" do
      base_channel = described_class.new(bus: bus)

      expect { base_channel.send(:send_message, nil) }.to raise_error(NotImplementedError)
    end

    it "can be implemented by subclass" do
      message = instance_double(Pocketrb::Bus::OutboundMessage)

      channel.send(:send_message, message)

      expect(channel.sent_messages).to include(message)
    end
  end

  describe "#run_inbound_loop" do
    it "raises NotImplementedError for base class" do
      base_channel = described_class.new(bus: bus)

      expect { base_channel.send(:run_inbound_loop) }.to raise_error(NotImplementedError)
    end

    it "can be implemented by subclass" do
      channel.send(:run_inbound_loop)

      expect(channel.inbound_loop_called).to be true
    end
  end

  describe "#create_inbound_message" do
    it "creates InboundMessage with channel name" do
      message = channel.send(
        :create_inbound_message,
        sender_id: "user123",
        chat_id: "chat456",
        content: "Hello"
      )

      expect(message).to be_a(Pocketrb::Bus::InboundMessage)
      expect(message.channel).to eq(:testchannel)
      expect(message.sender_id).to eq("user123")
      expect(message.chat_id).to eq("chat456")
      expect(message.content).to eq("Hello")
    end

    it "includes media when provided" do
      media = [instance_double(Pocketrb::Bus::Media)]
      message = channel.send(
        :create_inbound_message,
        sender_id: "user",
        chat_id: "chat",
        content: "Image",
        media: media
      )

      expect(message.media).to eq(media)
    end

    it "includes metadata when provided" do
      metadata = { source: "test" }
      message = channel.send(
        :create_inbound_message,
        sender_id: "user",
        chat_id: "chat",
        content: "Test",
        metadata: metadata
      )

      expect(message.metadata).to eq(metadata)
    end

    it "defaults media to empty array" do
      message = channel.send(
        :create_inbound_message,
        sender_id: "user",
        chat_id: "chat",
        content: "Test"
      )

      expect(message.media).to eq([])
    end

    it "defaults metadata to empty hash" do
      message = channel.send(
        :create_inbound_message,
        sender_id: "user",
        chat_id: "chat",
        content: "Test"
      )

      expect(message.metadata).to eq({})
    end
  end
end
