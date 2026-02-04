# frozen_string_literal: true

RSpec.describe Pocketrb::Agent::SpawnTool do
  let(:manager) { instance_double(Pocketrb::Agent::SubagentManager) }
  let(:context) do
    {
      workspace: Pathname.new("/workspace"),
      subagent_manager: manager,
      current_channel: :telegram,
      current_chat_id: "chat123"
    }
  end
  let(:tool) { described_class.new(context) }

  describe "#name" do
    it "returns spawn" do
      expect(tool.name).to eq("spawn")
    end
  end

  describe "#available?" do
    it "returns true when subagent_manager is available" do
      expect(tool.available?).to be true
    end

    it "returns false when subagent_manager is nil" do
      tool_without_manager = described_class.new(workspace: Pathname.new("/workspace"))

      expect(tool_without_manager.available?).to be false
    end
  end

  describe "#execute" do
    context "without subagent_manager" do
      it "returns error" do
        tool_without_manager = described_class.new(workspace: Pathname.new("/workspace"))

        result = tool_without_manager.execute(task: "Test task")

        expect(result).to include("Error:")
        expect(result).to include("Subagent spawning not available")
      end
    end

    context "with subagent_manager" do
      before do
        allow(manager).to receive(:spawn).and_return("agent_123")
      end

      it "spawns subagent with task" do
        tool.execute(task: "Complete this task")

        expect(manager).to have_received(:spawn).with(
          task: "Complete this task",
          skills: [],
          origin_channel: :telegram,
          origin_chat_id: "chat123"
        )
      end

      it "passes skills to spawned agent" do
        tool.execute(task: "Task", skills: %w[skill1 skill2])

        expect(manager).to have_received(:spawn).with(
          task: "Task",
          skills: %w[skill1 skill2],
          origin_channel: :telegram,
          origin_chat_id: "chat123"
        )
      end

      it "uses current channel and chat_id from context" do
        tool.execute(task: "Task")

        expect(manager).to have_received(:spawn).with(
          task: "Task",
          skills: [],
          origin_channel: :telegram,
          origin_chat_id: "chat123"
        )
      end

      it "defaults to cli channel when not in context" do
        context_no_channel = {
          workspace: Pathname.new("/workspace"),
          subagent_manager: manager
        }
        tool_no_channel = described_class.new(context_no_channel)

        tool_no_channel.execute(task: "Task")

        expect(manager).to have_received(:spawn).with(
          task: "Task",
          skills: [],
          origin_channel: :cli,
          origin_chat_id: "main"
        )
      end

      context "without waiting" do
        it "returns immediately with agent ID" do
          result = tool.execute(task: "Background task")

          expect(result).to include("Spawned subagent agent_123")
          expect(result).to include("Background task")
        end

        it "does not wait for completion" do
          allow(manager).to receive(:wait_for)

          tool.execute(task: "Task", wait: false)

          expect(manager).not_to have_received(:wait_for)
        end
      end

      context "with wait: true" do
        it "waits for subagent to complete" do
          allow(manager).to receive(:wait_for).and_return("Result from subagent")

          result = tool.execute(task: "Task", wait: true)

          expect(manager).to have_received(:wait_for).with("agent_123", timeout: 300)
          expect(result).to include("Subagent agent_123 completed")
          expect(result).to include("Result from subagent")
        end

        it "uses custom timeout" do
          allow(manager).to receive(:wait_for).and_return("Result")

          tool.execute(task: "Task", wait: true, timeout: 600)

          expect(manager).to have_received(:wait_for).with("agent_123", timeout: 600)
        end

        it "returns error when timeout occurs" do
          allow(manager).to receive(:wait_for).and_return(nil)

          result = tool.execute(task: "Task", wait: true)

          expect(result).to include("Error:")
          expect(result).to include("did not complete within timeout")
        end
      end
    end
  end
end
