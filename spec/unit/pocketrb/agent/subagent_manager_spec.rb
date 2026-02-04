# frozen_string_literal: true

RSpec.describe Pocketrb::Agent::SubagentManager do
  let(:bus) { instance_double(Pocketrb::Bus::MessageBus) }
  let(:provider) { instance_double(Pocketrb::Providers::Base) }
  let(:workspace) { Pathname.new("/tmp/workspace") }
  let(:parent_loop) do
    instance_double(
      Pocketrb::Agent::Loop,
      bus: bus,
      provider: provider,
      workspace: workspace,
      model: "claude-3-5-sonnet-20241022"
    )
  end
  let(:manager) { described_class.new(parent_loop: parent_loop) }

  describe "#initialize" do
    it "stores parent loop" do
      expect(manager.instance_variable_get(:@parent_loop)).to eq(parent_loop)
    end

    it "initializes empty active agents hash" do
      expect(manager.active_agents).to eq({})
    end
  end

  describe "#spawn" do
    before do
      # Stub async execution
      allow(manager).to receive(:Async).and_yield
      allow(manager).to receive(:run_agent)
      allow(Pocketrb.logger).to receive(:info)
    end

    it "generates unique agent ID" do
      agent_id = manager.spawn(
        task: "Test task",
        origin_channel: :telegram,
        origin_chat_id: "chat123"
      )

      expect(agent_id).to be_a(String)
      expect(agent_id.length).to eq(8)
    end

    it "stores agent info" do
      agent_id = manager.spawn(
        task: "Complete this",
        origin_channel: :telegram,
        origin_chat_id: "chat123",
        skills: %w[git search]
      )

      agent = manager.active_agents[agent_id]
      expect(agent[:task]).to eq("Complete this")
      expect(agent[:skills]).to eq(%w[git search])
      expect(agent[:origin_channel]).to eq(:telegram)
      expect(agent[:origin_chat_id]).to eq("chat123")
    end

    it "uses parent model by default" do
      agent_id = manager.spawn(
        task: "Task",
        origin_channel: :cli,
        origin_chat_id: "main"
      )

      agent = manager.active_agents[agent_id]
      expect(agent[:model]).to eq("claude-3-5-sonnet-20241022")
    end

    it "accepts custom model" do
      agent_id = manager.spawn(
        task: "Task",
        origin_channel: :cli,
        origin_chat_id: "main",
        model: "gpt-4"
      )

      agent = manager.active_agents[agent_id]
      expect(agent[:model]).to eq("gpt-4")
    end

    it "sets initial status to starting" do
      agent_id = manager.spawn(
        task: "Task",
        origin_channel: :cli,
        origin_chat_id: "main"
      )

      expect(manager.active_agents[agent_id][:status]).to eq(:starting)
    end

    it "sets started_at timestamp" do
      agent_id = manager.spawn(
        task: "Task",
        origin_channel: :cli,
        origin_chat_id: "main"
      )

      expect(manager.active_agents[agent_id][:started_at]).to be_a(Time)
    end

    it "returns agent ID" do
      agent_id = manager.spawn(
        task: "Task",
        origin_channel: :cli,
        origin_chat_id: "main"
      )

      expect(manager.active_agents).to have_key(agent_id)
    end

    it "logs spawn event" do
      manager.spawn(
        task: "Test task",
        origin_channel: :telegram,
        origin_chat_id: "chat123"
      )

      expect(Pocketrb.logger).to have_received(:info).with(/Spawned subagent/)
    end
  end

  describe "#get_status" do
    let!(:agent_id) do
      allow(manager).to receive(:Async).and_yield
      allow(manager).to receive(:run_agent)
      allow(Pocketrb.logger).to receive(:info)

      manager.spawn(
        task: "Task",
        origin_channel: :cli,
        origin_chat_id: "main"
      )
    end

    it "returns agent info" do
      status = manager.get_status(agent_id)

      expect(status).not_to be_nil
      expect(status[:task]).to eq("Task")
      expect(status[:status]).to eq(:starting)
    end

    it "returns nil for unknown agent" do
      status = manager.get_status("nonexistent")

      expect(status).to be_nil
    end

    it "returns a copy of agent info" do
      status = manager.get_status(agent_id)
      status[:status] = :modified

      actual_status = manager.get_status(agent_id)
      expect(actual_status[:status]).to eq(:starting)
    end
  end

  describe "#list_active" do
    before do
      allow(manager).to receive(:Async).and_yield
      allow(manager).to receive(:run_agent)
      allow(Pocketrb.logger).to receive(:info)
    end

    it "returns empty array when no agents" do
      expect(manager.list_active).to eq([])
    end

    it "returns only running agents" do
      agent1 = manager.spawn(
        task: "Task 1",
        origin_channel: :cli,
        origin_chat_id: "main"
      )
      agent2 = manager.spawn(
        task: "Task 2",
        origin_channel: :cli,
        origin_chat_id: "main"
      )

      # Update one to running
      manager.send(:update_status, agent1, :running)

      active = manager.list_active
      expect(active.length).to eq(1)
      expect(active.first[:id]).to eq(agent1)
    end

    it "excludes completed agents" do
      agent = manager.spawn(
        task: "Task",
        origin_channel: :cli,
        origin_chat_id: "main"
      )
      manager.send(:update_status, agent, :completed, result: "Done")

      expect(manager.list_active).to be_empty
    end
  end

  describe "#terminate" do
    let!(:agent_id) do
      allow(manager).to receive(:Async).and_yield
      allow(manager).to receive(:run_agent)
      allow(Pocketrb.logger).to receive(:info)

      manager.spawn(
        task: "Task",
        origin_channel: :cli,
        origin_chat_id: "main"
      )
    end

    it "sets status to terminated" do
      manager.terminate(agent_id)

      status = manager.get_status(agent_id)
      expect(status[:status]).to eq(:terminated)
    end

    it "handles unknown agent gracefully" do
      expect { manager.terminate("nonexistent") }.not_to raise_error
    end
  end

  describe "#wait_for" do
    let!(:agent_id) do
      allow(manager).to receive(:Async).and_yield
      allow(manager).to receive(:run_agent)
      allow(Pocketrb.logger).to receive(:info)

      manager.spawn(
        task: "Task",
        origin_channel: :cli,
        origin_chat_id: "main"
      )
    end

    it "returns result when agent completes" do
      manager.send(:update_status, agent_id, :completed, result: "Result text")

      result = manager.wait_for(agent_id, timeout: 1)

      expect(result).to eq("Result text")
    end

    it "returns nil for failed agent" do
      manager.send(:update_status, agent_id, :failed)

      result = manager.wait_for(agent_id, timeout: 1)

      expect(result).to be_nil
    end

    it "returns nil for terminated agent" do
      manager.send(:update_status, agent_id, :terminated)

      result = manager.wait_for(agent_id, timeout: 1)

      expect(result).to be_nil
    end

    it "returns nil when timeout exceeded" do
      allow(manager).to receive(:sleep)

      result = manager.wait_for(agent_id, timeout: 0.01)

      expect(result).to be_nil
    end

    it "returns nil for unknown agent" do
      result = manager.wait_for("nonexistent", timeout: 1)

      expect(result).to be_nil
    end
  end

  describe "#update_status" do
    let!(:agent_id) do
      allow(manager).to receive(:Async).and_yield
      allow(manager).to receive(:run_agent)
      allow(Pocketrb.logger).to receive(:info)

      manager.spawn(
        task: "Task",
        origin_channel: :cli,
        origin_chat_id: "main"
      )
    end

    it "updates agent status" do
      manager.send(:update_status, agent_id, :running)

      status = manager.get_status(agent_id)
      expect(status[:status]).to eq(:running)
    end

    it "updates result when provided" do
      manager.send(:update_status, agent_id, :completed, result: "Done")

      status = manager.get_status(agent_id)
      expect(status[:result]).to eq("Done")
    end

    it "sets completed_at for terminal statuses" do
      manager.send(:update_status, agent_id, :completed)

      status = manager.get_status(agent_id)
      expect(status[:completed_at]).to be_a(Time)
    end

    it "sets completed_at for failed status" do
      manager.send(:update_status, agent_id, :failed)

      status = manager.get_status(agent_id)
      expect(status[:completed_at]).to be_a(Time)
    end

    it "sets completed_at for terminated status" do
      manager.send(:update_status, agent_id, :terminated)

      status = manager.get_status(agent_id)
      expect(status[:completed_at]).to be_a(Time)
    end
  end

  describe "#build_subagent_prompt" do
    it "includes task description" do
      info = { task: "Analyze this code" }
      prompt = manager.send(:build_subagent_prompt, info)

      expect(prompt).to include("Analyze this code")
    end

    it "includes subagent guidelines" do
      info = { task: "Task" }
      prompt = manager.send(:build_subagent_prompt, info)

      expect(prompt).to include("specialized subagent")
      expect(prompt).to include("Focus only on the assigned task")
    end
  end
end
