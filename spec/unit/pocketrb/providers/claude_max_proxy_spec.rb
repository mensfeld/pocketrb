# frozen_string_literal: true

RSpec.describe Pocketrb::Providers::ClaudeMaxProxy do
  subject(:provider) { described_class.new(base_url: "http://localhost:3456/v1") }

  let(:url) { "http://localhost:3456/v1/chat/completions" }
  let(:messages) { [Pocketrb::Providers::Message.user("Read a file")] }
  let(:duplicate_args) { '{"path":"a","path":"b"}' }

  describe "#chat" do
    before do
      body = {
        choices: [{
          message: {
            content: nil,
            tool_calls: [{ id: "call_1", function: { name: "read_file", arguments: duplicate_args } }]
          },
          finish_reason: "tool_calls"
        }],
        usage: {}
      }
      stub_request(:post, url).to_return(status: 200, body: body.to_json)
    end

    it "keeps the last value of a duplicate key in tool arguments" do
      tool_call = provider.chat(messages: messages).tool_calls.first

      expect(tool_call.arguments).to eq({ "path" => "b" })
    end
  end

  describe "#chat_stream" do
    before do
      chunk = {
        choices: [{
          delta: {
            tool_calls: [{ index: 0, id: "call_1", function: { name: "read_file", arguments: duplicate_args } }]
          }
        }]
      }
      stub_request(:post, url).to_return(status: 200, body: "data: #{chunk.to_json}\n\ndata: [DONE]\n\n")
    end

    it "keeps the last value of a duplicate key in tool arguments" do
      tool_call = provider.chat_stream(messages: messages).tool_calls.first

      expect(tool_call.arguments).to eq({ "path" => "b" })
    end
  end
end
