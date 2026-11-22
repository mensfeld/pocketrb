# frozen_string_literal: true

RSpec.describe Pocketrb::CLI do
  describe "start --provider help" do
    it "lists every registered provider" do
      description = described_class.commands["start"].options[:provider].description

      expect(description).to include(*Pocketrb::Providers::Registry.new.available.map(&:to_s))
    end
  end

  describe "configuration errors" do
    def run_cli(*args)
      Dir.mktmpdir do |workspace|
        allow(Dir).to receive(:home).and_return(workspace)
        described_class.start(["chat", "--workspace", workspace, *args])
      end
    rescue SystemExit => e
      e.status
    end

    it "prints one line and exits 1 for an unknown provider" do
      status = nil

      expect { status = run_cli("--provider", "nope") }
        .to output("Error: Unknown provider: nope\n").to_stderr
      expect(status).to eq(1)
    end

    it "prints one line and exits 1 for a missing API key" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)
      status = nil

      expect { status = run_cli("--provider", "anthropic") }
        .to output("Error: ANTHROPIC_API_KEY is required for Pocketrb::Providers::Anthropic\n").to_stderr
      expect(status).to eq(1)
    end
  end
end
