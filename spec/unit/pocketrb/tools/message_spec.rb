# frozen_string_literal: true

RSpec.describe Pocketrb::Tools::Message do
  let(:bus) { instance_double(Pocketrb::Bus::MessageBus) }
  let(:context) do
    {
      bus: bus,
      default_channel: :telegram,
      default_chat_id: "12345"
    }
  end
  let(:tool) { described_class.new(context) }

  before do
    allow(bus).to receive(:publish_outbound)
  end

  describe "#name" do
    it "returns message" do
      expect(tool.name).to eq("message")
    end
  end

  describe "#available?" do
    it "returns true when bus is available" do
      expect(tool.available?).to be true
    end

    it "returns false when bus is nil" do
      tool_without_bus = described_class.new({})
      expect(tool_without_bus.available?).to be false
    end
  end

  describe "#execute" do
    context "with default channel and chat_id" do
      it "sends message using defaults" do
        result = tool.execute(content: "Hello!")

        expect(result).to include("Message sent to telegram:12345")
        expect(bus).to have_received(:publish_outbound) do |msg|
          expect(msg.channel).to eq(:telegram)
          expect(msg.chat_id).to eq("12345")
          expect(msg.content).to eq("Hello!")
        end
      end
    end

    context "with explicit channel and chat_id" do
      it "uses provided values" do
        result = tool.execute(
          content: "Custom message",
          channel: "whatsapp",
          chat_id: "67890"
        )

        expect(result).to include("Message sent to whatsapp:67890")
        expect(bus).to have_received(:publish_outbound) do |msg|
          expect(msg.channel).to eq(:whatsapp)
          expect(msg.chat_id).to eq("67890")
        end
      end
    end

    context "without channel" do
      it "returns error when no default channel" do
        tool_no_default = described_class.new(bus: bus, default_chat_id: "123")

        result = tool_no_default.execute(content: "Test")

        expect(result).to include("Error:")
        expect(result).to include("No channel specified")
      end
    end

    context "without chat_id" do
      it "returns error when no default chat_id" do
        tool_no_default = described_class.new(bus: bus, default_channel: :cli)

        result = tool_no_default.execute(content: "Test")

        expect(result).to include("Error:")
        expect(result).to include("No chat_id specified")
      end
    end

    context "without bus" do
      it "returns error" do
        tool_no_bus = described_class.new(default_channel: :cli, default_chat_id: "123")

        result = tool_no_bus.execute(content: "Test")

        expect(result).to include("Error:")
        expect(result).to include("Message bus not available")
      end
    end

    context "with message content" do
      it "handles multiline content" do
        content = "Line 1\nLine 2\nLine 3"

        result = tool.execute(content: content)

        expect(result).to include("Message sent")
        expect(bus).to have_received(:publish_outbound) do |msg|
          expect(msg.content).to eq(content)
        end
      end

      it "handles empty content" do
        result = tool.execute(content: "")

        expect(result).to include("Message sent")
      end
    end
  end
end
