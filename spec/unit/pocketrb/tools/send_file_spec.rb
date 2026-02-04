# frozen_string_literal: true

RSpec.describe Pocketrb::Tools::SendFile do
  let(:workspace) { Pathname.new(Dir.mktmpdir) }
  let(:bus) { instance_double(Pocketrb::Bus::MessageBus) }
  let(:context) do
    {
      workspace: workspace,
      bus: bus,
      default_channel: :telegram,
      default_chat_id: "12345"
    }
  end
  let(:tool) { described_class.new(context) }

  before do
    allow(bus).to receive(:publish_outbound)
  end

  after do
    FileUtils.rm_rf(workspace)
  end

  describe "#name" do
    it "returns send_file" do
      expect(tool.name).to eq("send_file")
    end
  end

  describe "#available?" do
    it "returns true when bus is available" do
      expect(tool.available?).to be true
    end

    it "returns false when bus is nil" do
      tool_without_bus = described_class.new(workspace: workspace)
      expect(tool_without_bus.available?).to be false
    end
  end

  describe "#execute" do
    let(:image_file) { workspace.join("test.png") }

    before do
      File.write(image_file, "fake image data")
    end

    context "with valid image file" do
      it "sends file via bus" do
        result = tool.execute(path: "test.png")

        expect(result).to include("Sent test.png to telegram")
        expect(bus).to have_received(:publish_outbound)
      end

      it "creates correct media object" do
        tool.execute(path: "test.png")

        expect(bus).to have_received(:publish_outbound) do |msg|
          expect(msg.channel).to eq(:telegram)
          expect(msg.chat_id).to eq("12345")
          expect(msg.media.first.type).to eq(:image)
          expect(msg.media.first.mime_type).to eq("image/png")
          expect(msg.media.first.filename).to eq("test.png")
        end
      end

      it "includes caption when provided" do
        tool.execute(path: "test.png", caption: "Check this out")

        expect(bus).to have_received(:publish_outbound) do |msg|
          expect(msg.content).to eq("Check this out")
        end
      end

      it "uses empty caption when not provided" do
        tool.execute(path: "test.png")

        expect(bus).to have_received(:publish_outbound) do |msg|
          expect(msg.content).to eq("")
        end
      end
    end

    context "with explicit channel and chat_id" do
      it "uses provided values" do
        tool.execute(path: "test.png", channel: "whatsapp", chat_id: "67890")

        expect(bus).to have_received(:publish_outbound) do |msg|
          expect(msg.channel).to eq(:whatsapp)
          expect(msg.chat_id).to eq("67890")
        end
      end
    end

    context "with different file types" do
      it "detects image type" do
        File.write(workspace.join("img.jpg"), "data")

        tool.execute(path: "img.jpg")

        expect(bus).to have_received(:publish_outbound) do |msg|
          expect(msg.media.first.type).to eq(:image)
          expect(msg.media.first.mime_type).to eq("image/jpeg")
        end
      end

      it "detects audio type" do
        File.write(workspace.join("audio.mp3"), "data")

        tool.execute(path: "audio.mp3")

        expect(bus).to have_received(:publish_outbound) do |msg|
          expect(msg.media.first.type).to eq(:audio)
          expect(msg.media.first.mime_type).to eq("audio/mpeg")
        end
      end

      it "detects video type" do
        File.write(workspace.join("video.mp4"), "data")

        tool.execute(path: "video.mp4")

        expect(bus).to have_received(:publish_outbound) do |msg|
          expect(msg.media.first.type).to eq(:video)
          expect(msg.media.first.mime_type).to eq("video/mp4")
        end
      end

      it "detects generic file type" do
        File.write(workspace.join("doc.pdf"), "data")

        tool.execute(path: "doc.pdf")

        expect(bus).to have_received(:publish_outbound) do |msg|
          expect(msg.media.first.type).to eq(:file)
          expect(msg.media.first.mime_type).to eq("application/pdf")
        end
      end
    end

    context "with invalid file" do
      it "returns error when file does not exist" do
        result = tool.execute(path: "nonexistent.png")

        expect(result).to include("Error:")
        expect(result).to include("File not found")
      end

      it "returns error when path is a directory" do
        dir = workspace.join("testdir")
        FileUtils.mkdir_p(dir)

        result = tool.execute(path: "testdir")

        expect(result).to include("Error:")
        expect(result).to include("Not a file")
      end

      it "returns error when file extension is not allowed" do
        File.write(workspace.join("test.exe"), "data")

        result = tool.execute(path: "test.exe")

        expect(result).to include("Error:")
        expect(result).to include("File type not allowed")
      end

      it "returns error when file is too large" do
        large_file = workspace.join("large.png")
        File.write(large_file, "x" * 51_000_000)

        result = tool.execute(path: "large.png")

        expect(result).to include("Error:")
        expect(result).to include("File too large")
        expect(result).to include("Max 50MB")
      end
    end

    context "without bus" do
      it "returns error about message bus when channel/chat_id are provided" do
        tool_without_bus = described_class.new(workspace: workspace)
        File.write(workspace.join("test.png"), "data")

        result = tool_without_bus.execute(
          path: "test.png",
          channel: "telegram",
          chat_id: "12345"
        )

        expect(result).to include("Error:")
        expect(result).to include("Message bus not available")
      end
    end

    context "without defaults" do
      let(:context_no_defaults) do
        {
          workspace: workspace,
          bus: bus
        }
      end
      let(:tool_no_defaults) { described_class.new(context_no_defaults) }

      before do
        File.write(workspace.join("test.png"), "data")
      end

      it "returns error when no channel specified" do
        result = tool_no_defaults.execute(path: "test.png")

        expect(result).to include("Error:")
        expect(result).to include("No channel specified")
      end

      it "returns error when no chat_id specified" do
        result = tool_no_defaults.execute(path: "test.png", channel: "telegram")

        expect(result).to include("Error:")
        expect(result).to include("No chat_id specified")
      end
    end

    context "with absolute path" do
      it "uses absolute path directly" do
        abs_file = Pathname.new(Dir.mktmpdir).join("absolute.png")
        File.write(abs_file, "data")

        tool.execute(path: abs_file.to_s)

        expect(bus).to have_received(:publish_outbound)
      ensure
        FileUtils.rm_f(abs_file)
      end
    end
  end
end
