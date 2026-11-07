# frozen_string_literal: true

require "tmpdir"

RSpec.describe Pocketrb::Providers::ClaudeCLI do
  subject(:provider) { described_class.new }

  let(:messages) { [Pocketrb::Providers::Message.user("Hello")] }
  let(:result_event) { { "type" => "result", "result" => "Hi", "usage" => {} }.to_json }

  around do |example|
    Dir.mktmpdir do |dir|
      cli = File.join(dir, "claude")
      File.write(cli, "#!/bin/sh\n")
      File.chmod(0o755, cli)
      original_path = ENV.fetch("PATH", nil)
      ENV["PATH"] = "#{dir}:#{original_path}"
      example.run
    ensure
      ENV["PATH"] = original_path
    end
  end

  before do
    allow(Open3).to receive(:popen3).and_return(
      [StringIO.new, StringIO.new("#{result_event}\n"), StringIO.new, instance_double(Thread, alive?: true)]
    )
  end

  describe "#chat" do
    it "reports the current model ID for the sonnet alias" do
      expect(provider.chat(messages: messages, model: "sonnet").model).to eq("claude-sonnet-5-5")
    end

    it "keeps an unknown model name as is" do
      expect(provider.chat(messages: messages, model: "custom-model").model).to eq("custom-model")
    end

    context "with a code block tool call that has a duplicate key" do
      let(:result_event) do
        text = "```json\n{\"tool\":\"read_file\",\"input\":{\"path\":\"a\",\"path\":\"b\"}}\n```"
        { "type" => "result", "result" => text, "usage" => {} }.to_json
      end

      it "keeps the last value" do
        tool_call = provider.chat(messages: messages).tool_calls.first

        expect(tool_call.arguments).to eq({ "path" => "b" })
      end
    end

    context "with an inline tool call that has a duplicate key" do
      let(:result_event) do
        { "type" => "result", "result" => '{"tool":"read_file","tool":"list_dir"}', "usage" => {} }.to_json
      end

      it "keeps the tool call" do
        expect(provider.chat(messages: messages).tool_calls.map(&:name)).to eq(["list_dir"])
      end
    end
  end
end
