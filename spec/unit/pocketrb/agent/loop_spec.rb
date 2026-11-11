# frozen_string_literal: true

require "spec_helper"

RSpec.describe Pocketrb::Agent::Loop do
  let(:workspace) { Dir.mktmpdir("pocketrb-loop") }
  let(:image_path) { File.join(workspace, "photo.png").tap { |p| File.binwrite(p, "\x89PNG\r\n\x1a\nfake") } }
  let(:agent) { build_agent }

  def build_agent
    described_class.new(
      bus: Pocketrb::Bus::MessageBus.new,
      provider: Pocketrb::Providers::Anthropic.new,
      workspace: workspace,
      enable_compaction: false
    )
  end

  before do
    ENV["ANTHROPIC_API_KEY"] = "test-key"
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(
        status: 200,
        body: {
          "content" => [{ "type" => "text", "text" => "Got it" }],
          "stop_reason" => "end_turn",
          "usage" => { "input_tokens" => 1, "output_tokens" => 1 },
          "model" => "claude-sonnet-5-5"
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  after do
    ENV.delete("ANTHROPIC_API_KEY")
    FileUtils.rm_rf(workspace)
  end

  describe "#process_message" do
    def inbound(content, media: [])
      Pocketrb::Bus::InboundMessage.new(
        channel: :cli, sender_id: "user", chat_id: "chat", content: content, media: media
      )
    end

    it "sends an image and a non-image attachment to the provider" do
      media = [
        Pocketrb::Bus::Media.new(type: :image, path: image_path, mime_type: "image/png", filename: "photo.png"),
        Pocketrb::Bus::Media.new(type: :file, path: "/tmp/missing.pdf", mime_type: "application/pdf",
                                 filename: "report.pdf")
      ]

      response = agent.process_message(inbound("What is this?", media: media))

      expect(response.content).to eq("Got it")
      expect(WebMock).to(have_requested(:post, "https://api.anthropic.com/v1/messages").with do |req|
        JSON.parse(req.body)["messages"] == [
          {
            "role" => "user",
            "content" => [
              { "type" => "text", "text" => "What is this?" },
              { "type" => "image",
                "source" => { "type" => "base64", "media_type" => "image/png", "data" => "iVBORw0KGgpmYWtl" } },
              { "type" => "text", "text" => "[Attached: report.pdf (application/pdf)]" }
            ]
          }
        ]
      end)
    end

    it "sends earlier media as text after the session is reloaded from storage" do
      media = [Pocketrb::Bus::Media.new(type: :image, path: image_path, mime_type: "image/png", filename: "photo.png")]
      agent.process_message(inbound("First", media: media))

      build_agent.process_message(inbound("Second"))

      expect(WebMock).to(have_requested(:post, "https://api.anthropic.com/v1/messages").with do |req|
        JSON.parse(req.body)["messages"] == [
          { "role" => "user", "content" => "First\n[Previous image: photo.png]" },
          { "role" => "assistant", "content" => [{ "type" => "text", "text" => "Got it" }] },
          { "role" => "user", "content" => "Second" }
        ]
      end)
    end
  end
end
