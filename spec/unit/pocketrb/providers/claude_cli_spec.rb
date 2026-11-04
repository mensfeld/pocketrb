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
  end
end
