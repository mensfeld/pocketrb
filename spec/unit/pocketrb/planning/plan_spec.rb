# frozen_string_literal: true

RSpec.describe Pocketrb::Planning::Plan do
  let(:plan) do
    described_class.new(
      name: "test-plan",
      description: "A test plan",
      steps: ["Step 1", "Step 2", "Step 3"]
    )
  end

  describe "#initialize" do
    it "sets name" do
      expect(plan.name).to eq("test-plan")
    end

    it "sets description" do
      expect(plan.description).to eq("A test plan")
    end

    it "creates steps from strings" do
      expect(plan.steps.length).to eq(3)
      expect(plan.steps.first).to be_a(described_class::Step)
      expect(plan.steps.first.description).to eq("Step 1")
    end

    it "sets step indices" do
      expect(plan.steps[0].index).to eq(0)
      expect(plan.steps[1].index).to eq(1)
      expect(plan.steps[2].index).to eq(2)
    end

    it "defaults status to DRAFT" do
      expect(plan.status).to eq(described_class::PlanStatus::DRAFT)
    end

    it "accepts custom status" do
      p = described_class.new(
        name: "plan",
        steps: [],
        status: described_class::PlanStatus::ACTIVE
      )

      expect(p.status).to eq(described_class::PlanStatus::ACTIVE)
    end

    it "defaults metadata to empty hash" do
      expect(plan.metadata).to eq({})
    end

    it "accepts metadata" do
      p = described_class.new(
        name: "plan",
        steps: [],
        metadata: { key: "value" }
      )

      expect(p.metadata).to eq({ key: "value" })
    end

    it "sets created_at timestamp" do
      expect(plan.created_at).to be_a(Time)
    end
  end

  describe "Step" do
    let(:step) do
      described_class::Step.new(
        index: 0,
        description: "Test step"
      )
    end

    describe "#initialize" do
      it "sets index and description" do
        expect(step.index).to eq(0)
        expect(step.description).to eq("Test step")
      end

      it "defaults status to PENDING" do
        expect(step.status).to eq(described_class::StepStatus::PENDING)
      end

      it "defaults notes to nil" do
        expect(step.notes).to be_nil
      end

      it "defaults completed_at to nil" do
        expect(step.completed_at).to be_nil
      end
    end

    describe "#pending?" do
      it "returns true when status is PENDING" do
        expect(step.pending?).to be true
      end

      it "returns false when status is not PENDING" do
        s = described_class::Step.new(
          index: 0,
          description: "test",
          status: described_class::StepStatus::COMPLETED
        )

        expect(s.pending?).to be false
      end
    end

    describe "#completed?" do
      it "returns true when status is COMPLETED" do
        s = described_class::Step.new(
          index: 0,
          description: "test",
          status: described_class::StepStatus::COMPLETED
        )

        expect(s.completed?).to be true
      end

      it "returns false when status is not COMPLETED" do
        expect(step.completed?).to be false
      end
    end

    describe "#failed?" do
      it "returns true when status is FAILED" do
        s = described_class::Step.new(
          index: 0,
          description: "test",
          status: described_class::StepStatus::FAILED
        )

        expect(s.failed?).to be true
      end

      it "returns false when status is not FAILED" do
        expect(step.failed?).to be false
      end
    end

    describe "#to_h" do
      it "converts to hash" do
        hash = step.to_h

        expect(hash[:index]).to eq(0)
        expect(hash[:description]).to eq("Test step")
        expect(hash[:status]).to eq(described_class::StepStatus::PENDING)
      end

      it "omits nil values" do
        hash = step.to_h

        expect(hash).not_to have_key(:notes)
        expect(hash).not_to have_key(:completed_at)
      end

      it "includes completed_at in ISO8601 format when present" do
        time = Time.now
        s = described_class::Step.new(
          index: 0,
          description: "test",
          completed_at: time
        )

        expect(s.to_h[:completed_at]).to eq(time.iso8601)
      end
    end
  end

  describe "#add_step" do
    it "adds a step to the plan" do
      plan.add_step("Step 4")

      expect(plan.steps.length).to eq(4)
      expect(plan.steps.last.description).to eq("Step 4")
    end

    it "sets correct index for new step" do
      plan.add_step("Step 4")

      expect(plan.steps.last.index).to eq(3)
    end

    it "returns the new step" do
      step = plan.add_step("Step 4")

      expect(step).to be_a(described_class::Step)
      expect(step.description).to eq("Step 4")
    end
  end

  describe "#add_steps" do
    it "adds multiple steps" do
      plan.add_steps(["Step 4", "Step 5"])

      expect(plan.steps.length).to eq(5)
      expect(plan.steps[-2].description).to eq("Step 4")
      expect(plan.steps[-1].description).to eq("Step 5")
    end
  end

  describe "#update_step" do
    it "updates step status" do
      plan.update_step(0, status: described_class::StepStatus::COMPLETED)

      expect(plan.steps[0].status).to eq(described_class::StepStatus::COMPLETED)
    end

    it "updates step notes" do
      plan.update_step(0, status: described_class::StepStatus::COMPLETED, notes: "Done")

      expect(plan.steps[0].notes).to eq("Done")
    end

    it "sets completed_at when status is COMPLETED" do
      plan.update_step(0, status: described_class::StepStatus::COMPLETED)

      expect(plan.steps[0].completed_at).to be_a(Time)
    end

    it "does not set completed_at for other statuses" do
      plan.update_step(0, status: described_class::StepStatus::IN_PROGRESS)

      expect(plan.steps[0].completed_at).to be_nil
    end

    it "returns nil for invalid index" do
      result = plan.update_step(99, status: described_class::StepStatus::COMPLETED)

      expect(result).to be_nil
    end

    it "preserves existing notes when not provided" do
      plan.update_step(0, status: described_class::StepStatus::IN_PROGRESS, notes: "Working")
      plan.update_step(0, status: described_class::StepStatus::COMPLETED)

      expect(plan.steps[0].notes).to eq("Working")
    end
  end

  describe "#complete_step" do
    it "marks step as completed" do
      plan.complete_step(0)

      expect(plan.steps[0].status).to eq(described_class::StepStatus::COMPLETED)
    end

    it "accepts optional notes" do
      plan.complete_step(0, notes: "All done")

      expect(plan.steps[0].notes).to eq("All done")
    end
  end

  describe "#fail_step" do
    it "marks step as failed" do
      plan.fail_step(0)

      expect(plan.steps[0].status).to eq(described_class::StepStatus::FAILED)
    end

    it "accepts optional notes" do
      plan.fail_step(0, notes: "Error occurred")

      expect(plan.steps[0].notes).to eq("Error occurred")
    end
  end

  describe "#skip_step" do
    it "marks step as skipped" do
      plan.skip_step(0)

      expect(plan.steps[0].status).to eq(described_class::StepStatus::SKIPPED)
    end

    it "accepts optional notes" do
      plan.skip_step(0, notes: "Not needed")

      expect(plan.steps[0].notes).to eq("Not needed")
    end
  end

  describe "#next_step" do
    it "returns first pending step" do
      plan.complete_step(0)

      next_step = plan.next_step

      expect(next_step.index).to eq(1)
      expect(next_step.pending?).to be true
    end

    it "returns nil when all steps are complete" do
      plan.complete_step(0)
      plan.complete_step(1)
      plan.complete_step(2)

      expect(plan.next_step).to be_nil
    end
  end

  describe "#current_step" do
    it "returns in-progress step when present" do
      plan.update_step(1, status: described_class::StepStatus::IN_PROGRESS)

      expect(plan.current_step.index).to eq(1)
    end

    it "returns next pending step when no in-progress step" do
      expect(plan.current_step.index).to eq(0)
    end

    it "returns nil when all steps are complete" do
      plan.complete_step(0)
      plan.complete_step(1)
      plan.complete_step(2)

      expect(plan.current_step).to be_nil
    end
  end

  describe "#complete?" do
    it "returns false when steps are pending" do
      expect(plan.complete?).to be false
    end

    it "returns true when all steps are completed" do
      plan.complete_step(0)
      plan.complete_step(1)
      plan.complete_step(2)

      expect(plan.complete?).to be true
    end

    it "returns true for plan with no steps" do
      p = described_class.new(name: "empty", steps: [])

      expect(p.complete?).to be true
    end
  end

  describe "#failed?" do
    it "returns false when no steps failed" do
      expect(plan.failed?).to be false
    end

    it "returns true when any step failed" do
      plan.fail_step(1)

      expect(plan.failed?).to be true
    end
  end

  describe "#progress" do
    it "returns 0 for empty plan" do
      p = described_class.new(name: "empty", steps: [])

      expect(p.progress).to eq(0)
    end

    it "calculates percentage of completed steps" do
      plan.complete_step(0)

      expect(plan.progress).to eq(33)
    end

    it "returns 100 when all complete" do
      plan.complete_step(0)
      plan.complete_step(1)
      plan.complete_step(2)

      expect(plan.progress).to eq(100)
    end
  end

  describe "#activate!" do
    it "sets status to ACTIVE" do
      plan.activate!

      expect(plan.status).to eq(described_class::PlanStatus::ACTIVE)
    end
  end

  describe "#mark_complete!" do
    it "sets status to COMPLETED" do
      plan.mark_complete!

      expect(plan.status).to eq(described_class::PlanStatus::COMPLETED)
    end
  end

  describe "#mark_failed!" do
    it "sets status to FAILED" do
      plan.mark_failed!

      expect(plan.status).to eq(described_class::PlanStatus::FAILED)
    end
  end

  describe "#cancel!" do
    it "sets status to CANCELLED" do
      plan.cancel!

      expect(plan.status).to eq(described_class::PlanStatus::CANCELLED)
    end
  end

  describe "#to_markdown" do
    it "includes plan name" do
      markdown = plan.to_markdown

      expect(markdown).to include("# Plan: test-plan")
    end

    it "includes description when present" do
      markdown = plan.to_markdown

      expect(markdown).to include("A test plan")
    end

    it "includes status and progress" do
      markdown = plan.to_markdown

      expect(markdown).to include("Status: draft")
      expect(markdown).to include("Progress: 0%")
    end

    it "includes all steps with checkboxes" do
      markdown = plan.to_markdown

      expect(markdown).to include("[ ] 1. Step 1")
      expect(markdown).to include("[ ] 2. Step 2")
      expect(markdown).to include("[ ] 3. Step 3")
    end

    it "uses [x] for completed steps" do
      plan.complete_step(0)
      markdown = plan.to_markdown

      expect(markdown).to include("[x] 1. Step 1")
    end

    it "uses [~] for in-progress steps" do
      plan.update_step(0, status: described_class::StepStatus::IN_PROGRESS)
      markdown = plan.to_markdown

      expect(markdown).to include("[~] 1. Step 1")
    end

    it "uses [!] for failed steps" do
      plan.fail_step(0)
      markdown = plan.to_markdown

      expect(markdown).to include("[!] 1. Step 1")
    end

    it "uses [-] for skipped steps" do
      plan.skip_step(0)
      markdown = plan.to_markdown

      expect(markdown).to include("[-] 1. Step 1")
    end

    it "includes notes when present" do
      plan.complete_step(0, notes: "Completed successfully")
      markdown = plan.to_markdown

      expect(markdown).to include("Notes: Completed successfully")
    end
  end

  describe "#to_h" do
    it "converts to hash" do
      hash = plan.to_h

      expect(hash[:name]).to eq("test-plan")
      expect(hash[:description]).to eq("A test plan")
      expect(hash[:status]).to eq(described_class::PlanStatus::DRAFT)
      expect(hash[:steps]).to be_an(Array)
      expect(hash[:metadata]).to eq({})
      expect(hash[:progress]).to eq(0)
    end

    it "includes created_at in ISO8601 format" do
      hash = plan.to_h

      expect(hash[:created_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end

    it "includes steps as hashes" do
      hash = plan.to_h

      expect(hash[:steps].first).to be_a(Hash)
      expect(hash[:steps].first[:description]).to eq("Step 1")
    end
  end

  describe ".from_h" do
    let(:hash) do
      {
        name: "restored-plan",
        description: "Restored from hash",
        steps: [
          { index: 0, description: "Step 1", status: "completed", notes: "Done" },
          { index: 1, description: "Step 2", status: "pending" }
        ],
        status: "active",
        metadata: { key: "value" },
        created_at: "2024-01-01T12:00:00Z"
      }
    end

    it "creates plan from hash" do
      p = described_class.from_h(hash)

      expect(p.name).to eq("restored-plan")
      expect(p.description).to eq("Restored from hash")
      expect(p.status).to eq("active")
      expect(p.metadata).to eq({ key: "value" })
    end

    it "restores steps" do
      p = described_class.from_h(hash)

      expect(p.steps.length).to eq(2)
      expect(p.steps[0].description).to eq("Step 1")
      expect(p.steps[0].status).to eq("completed")
      expect(p.steps[0].notes).to eq("Done")
    end

    it "restores created_at timestamp" do
      p = described_class.from_h(hash)

      expect(p.created_at).to be_a(Time)
      expect(p.created_at.iso8601).to eq("2024-01-01T12:00:00Z")
    end

    it "handles string keys" do
      string_hash = {
        "name" => "plan",
        "description" => "desc",
        "steps" => [
          { "index" => 0, "description" => "Step", "status" => "pending" }
        ],
        "status" => "draft",
        "metadata" => {}
      }

      p = described_class.from_h(string_hash)

      expect(p.name).to eq("plan")
      expect(p.steps.first.description).to eq("Step")
    end
  end

  describe "constants" do
    it "defines StepStatus constants" do
      expect(described_class::StepStatus::PENDING).to eq("pending")
      expect(described_class::StepStatus::IN_PROGRESS).to eq("in_progress")
      expect(described_class::StepStatus::COMPLETED).to eq("completed")
      expect(described_class::StepStatus::FAILED).to eq("failed")
      expect(described_class::StepStatus::SKIPPED).to eq("skipped")
    end

    it "defines PlanStatus constants" do
      expect(described_class::PlanStatus::DRAFT).to eq("draft")
      expect(described_class::PlanStatus::ACTIVE).to eq("active")
      expect(described_class::PlanStatus::COMPLETED).to eq("completed")
      expect(described_class::PlanStatus::FAILED).to eq("failed")
      expect(described_class::PlanStatus::CANCELLED).to eq("cancelled")
    end
  end
end
