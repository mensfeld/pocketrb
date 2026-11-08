# frozen_string_literal: true

RSpec.describe Pocketrb::Channels::WhatsApp do
  let(:bus) { instance_double(Pocketrb::Bus::MessageBus) }
  let(:channel) { described_class.new(bus: bus) }

  describe "#run" do
    context "when websocket-client-simple is not installed" do
      before do
        allow(channel).to receive(:require).with("websocket-client-simple").and_raise(LoadError)
      end

      it "raises a LoadError naming the gem" do
        expect { channel.run }.to raise_error(LoadError, /gem "websocket-client-simple".*Gemfile/)
      end

      it "raises MissingDependencyError" do
        expect { channel.run }.to raise_error(Pocketrb::MissingDependencyError)
      end

      it "does not start the channel" do
        expect { channel.run }.to raise_error(LoadError)
        expect(channel).not_to be_running
      end
    end
  end
end
