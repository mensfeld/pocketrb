# frozen_string_literal: true

RSpec.describe Pocketrb::CLI::Gateway do
  let(:workspace) { Dir.mktmpdir }
  let(:agent_loop) { instance_double(Pocketrb::Agent::Loop, run: nil, stop: nil, sessions: nil) }
  let(:started) { [] }
  let(:telegram) { instance_double(Pocketrb::Channels::Telegram, name: :telegram, stop: nil) }

  def stub_whatsapp(available:)
    allow(Pocketrb::Channels::WhatsApp).to receive(:new).and_wrap_original do |original, **kwargs|
      original.call(**kwargs).tap do |channel|
        allow(channel).to receive(:available?).and_return(available)
        allow(channel).to receive(:run) { started << :whatsapp }
      end
    end
  end

  def run_gateway(*args)
    allow(described_class).to receive(:new).and_wrap_original do |original, *new_args|
      original.call(*new_args).tap { |command| allow(command).to receive(:sleep).and_raise(Interrupt) }
    end
    Pocketrb::CLI.start(["gateway", "--workspace", workspace, "--no-enable-cron", "--no-enable-heartbeat", *args])
  end

  before do
    allow(Pocketrb::Providers::Registry).to receive(:get).and_return(instance_double(Pocketrb::Providers::Base))
    allow(Pocketrb::Agent::Loop).to receive(:new).and_return(agent_loop)
    allow(Pocketrb::Channels::Telegram).to receive(:new).and_return(telegram)
    allow(telegram).to receive(:status_context=)
    allow(telegram).to receive(:run) do
      started << :telegram
      sleep
    end
  end

  after do
    FileUtils.rm_rf(workspace)
  end

  describe "#call" do
    it "starts WhatsApp while Telegram blocks" do
      stub_whatsapp(available: true)
      expect { run_gateway("--telegram-token", "token") }.to output(/WhatsApp: enabled/).to_stdout
      expect(started).to eq(%i[telegram whatsapp])
    end

    it "starts cron and heartbeat while Telegram blocks" do
      stub_whatsapp(available: true)
      cron = instance_double(Pocketrb::Cron::Service, start: nil, stop: nil)
      heartbeat = instance_double(Pocketrb::Heartbeat::Service, start: nil, stop: nil)
      allow(Pocketrb::Cron::Service).to receive(:new).and_return(cron)
      allow(Pocketrb::Heartbeat::Service).to receive(:new).and_return(heartbeat)
      allow(agent_loop).to receive(:tools).and_return(instance_double(Pocketrb::Tools::Registry, update_context: nil))
      expect { run_gateway("--telegram-token", "token", "--enable-cron", "--enable-heartbeat") }.to output.to_stdout
      expect(cron).to have_received(:start)
      expect(heartbeat).to have_received(:start)
    end

    it "logs a failing channel and keeps starting the others" do
      stub_whatsapp(available: true)
      allow(telegram).to receive(:run).and_raise(StandardError, "boom")
      allow(Pocketrb.logger).to receive(:error)
      expect { run_gateway("--telegram-token", "token") }.to output.to_stdout
      expect(Pocketrb.logger).to have_received(:error).with("telegram channel stopped: boom")
      expect(started).to eq(%i[whatsapp])
    end

    it "stops channels and the agent loop on interrupt" do
      stub_whatsapp(available: true)
      expect { run_gateway("--telegram-token", "token") }.to output(/Shutting down gateway/).to_stdout
      expect(telegram).to have_received(:stop)
      expect(agent_loop).to have_received(:stop)
    end

    it "skips WhatsApp with a warning when the default bridge lacks the gem" do
      stub_whatsapp(available: false)
      expect { run_gateway("--telegram-token", "token") }
        .to output(/WhatsApp: skipped \(websocket-client-simple gem not installed\)/).to_stdout
      expect(started).to eq(%i[telegram])
    end

    it "keeps running without Telegram when the default bridge lacks the gem" do
      stub_whatsapp(available: false)
      expect { run_gateway }.to output(/WhatsApp: skipped.*Shutting down gateway/m).to_stdout
    end

    it "raises MissingDependencyError when an explicit bridge lacks the gem" do
      stub_whatsapp(available: false)
      expect { run_gateway("--whatsapp-bridge", "ws://localhost:3001") }
        .to raise_error(Pocketrb::MissingDependencyError, /websocket-client-simple/)
        .and output.to_stdout
    end
  end
end
