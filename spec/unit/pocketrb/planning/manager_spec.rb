# frozen_string_literal: true

RSpec.describe Pocketrb::Planning::Manager do
  let(:workspace) { Pathname.new(Dir.mktmpdir) }
  let(:manager) { described_class.new(workspace: workspace) }
  let(:plans_dir) { workspace.join(".pocketrb", "plans") }

  after do
    FileUtils.rm_rf(workspace)
  end

  describe "#initialize" do
    it "creates plans directory" do
      manager # trigger initialization

      expect(plans_dir).to exist
      expect(plans_dir).to be_directory
    end

    it "stores workspace" do
      expect(manager.workspace).to eq(workspace)
    end
  end

  describe "#create_plan" do
    it "creates new plan" do
      plan = manager.create_plan(
        name: "test-plan",
        steps: ["Step 1", "Step 2"],
        description: "Test plan"
      )

      expect(plan).to be_a(Pocketrb::Planning::Plan)
      expect(plan.name).to eq("test-plan")
      expect(plan.steps.length).to eq(2)
    end

    it "persists plan to file" do
      manager.create_plan(name: "test", steps: ["Step 1"])

      file = plans_dir.join("test.json")
      expect(file).to exist
    end

    it "raises error for duplicate plan name" do
      manager.create_plan(name: "duplicate", steps: ["Step 1"])

      expect do
        manager.create_plan(name: "duplicate", steps: ["Step 2"])
      end.to raise_error(Pocketrb::Error, /already exists/)
    end

    it "sanitizes plan name for filename" do
      manager.create_plan(name: "test/plan:name", steps: ["Step 1"])

      expect(plans_dir.join("test_plan_name.json")).to exist
    end
  end

  describe "#get_plan" do
    it "returns existing plan" do
      created = manager.create_plan(name: "test", steps: ["Step 1"])
      retrieved = manager.get_plan("test")

      expect(retrieved.name).to eq(created.name)
    end

    it "returns nil for non-existent plan" do
      expect(manager.get_plan("nonexistent")).to be_nil
    end

    it "loads plan from disk" do
      manager.create_plan(name: "test", steps: ["Step 1"])

      # Create new manager to test file loading
      manager2 = described_class.new(workspace: workspace)
      plan = manager2.get_plan("test")

      expect(plan).not_to be_nil
      expect(plan.name).to eq("test")
    end

    it "caches plans" do
      manager.create_plan(name: "test", steps: ["Step 1"])

      plan1 = manager.get_plan("test")
      plan2 = manager.get_plan("test")

      expect(plan1).to equal(plan2)
    end
  end

  describe "#update_plan" do
    before do
      manager.create_plan(name: "test", steps: ["Step 1", "Step 2"])
    end

    it "completes a step" do
      manager.update_plan(name: "test", completed_step: 0)

      updated = manager.get_plan("test")
      expect(updated.steps[0].status).to eq(Pocketrb::Planning::Plan::StepStatus::COMPLETED)
    end

    it "adds notes to completed step" do
      manager.update_plan(name: "test", completed_step: 0, notes: "Done well")

      updated = manager.get_plan("test")
      expect(updated.steps[0].notes).to eq("Done well")
    end

    it "adds new steps" do
      manager.update_plan(name: "test", new_steps: ["Step 3", "Step 4"])

      updated = manager.get_plan("test")
      expect(updated.steps.length).to eq(4)
    end

    it "auto-completes plan when all steps done" do
      manager.activate_plan("test")
      manager.update_plan(name: "test", completed_step: 0)
      manager.update_plan(name: "test", completed_step: 1)

      plan = manager.get_plan("test")
      expect(plan.status).to eq(Pocketrb::Planning::Plan::PlanStatus::COMPLETED)
    end

    it "raises error for non-existent plan" do
      expect do
        manager.update_plan(name: "nonexistent", completed_step: 0)
      end.to raise_error(Pocketrb::Error, /not found/)
    end

    it "persists changes" do
      manager.update_plan(name: "test", completed_step: 0)

      manager2 = described_class.new(workspace: workspace)
      loaded = manager2.get_plan("test")
      expect(loaded.steps[0].status).to eq(Pocketrb::Planning::Plan::StepStatus::COMPLETED)
    end
  end

  describe "#fail_step" do
    before do
      manager.create_plan(name: "test", steps: ["Step 1"])
    end

    it "marks step as failed" do
      manager.fail_step(name: "test", step_index: 0)

      plan = manager.get_plan("test")
      expect(plan.steps[0].status).to eq(Pocketrb::Planning::Plan::StepStatus::FAILED)
    end

    it "adds notes to failed step" do
      manager.fail_step(name: "test", step_index: 0, notes: "Error occurred")

      plan = manager.get_plan("test")
      expect(plan.steps[0].notes).to eq("Error occurred")
    end

    it "raises error for non-existent plan" do
      expect do
        manager.fail_step(name: "nonexistent", step_index: 0)
      end.to raise_error(Pocketrb::Error, /not found/)
    end
  end

  describe "#activate_plan" do
    let!(:plan) { manager.create_plan(name: "test", steps: ["Step 1"]) }

    it "activates plan" do
      # Plan starts in DRAFT status
      expect(plan.status).to eq(Pocketrb::Planning::Plan::PlanStatus::DRAFT)

      manager.activate_plan("test")

      updated = manager.get_plan("test")
      expect(updated.status).to eq(Pocketrb::Planning::Plan::PlanStatus::ACTIVE)
    end

    it "raises error for non-existent plan" do
      expect do
        manager.activate_plan("nonexistent")
      end.to raise_error(Pocketrb::Error, /not found/)
    end
  end

  describe "#mark_complete" do
    before do
      manager.create_plan(name: "test", steps: ["Step 1"])
      manager.activate_plan("test")
    end

    it "marks plan as complete" do
      manager.mark_complete("test")

      plan = manager.get_plan("test")
      expect(plan.status).to eq(Pocketrb::Planning::Plan::PlanStatus::COMPLETED)
    end

    it "raises error for non-existent plan" do
      expect do
        manager.mark_complete("nonexistent")
      end.to raise_error(Pocketrb::Error, /not found/)
    end
  end

  describe "#cancel_plan" do
    before do
      manager.create_plan(name: "test", steps: ["Step 1"])
      manager.activate_plan("test")
    end

    it "cancels plan" do
      manager.cancel_plan("test")

      plan = manager.get_plan("test")
      expect(plan.status).to eq(Pocketrb::Planning::Plan::PlanStatus::CANCELLED)
    end

    it "raises error for non-existent plan" do
      expect do
        manager.cancel_plan("nonexistent")
      end.to raise_error(Pocketrb::Error, /not found/)
    end
  end

  describe "#delete_plan" do
    it "removes plan from disk" do
      manager.create_plan(name: "test", steps: ["Step 1"])
      file = plans_dir.join("test.json")
      expect(file).to exist

      manager.delete_plan("test")

      expect(file).not_to exist
    end

    it "removes plan from cache" do
      manager.create_plan(name: "test", steps: ["Step 1"])
      manager.delete_plan("test")

      expect(manager.get_plan("test")).to be_nil
    end

    it "handles non-existent plan gracefully" do
      expect { manager.delete_plan("nonexistent") }.not_to raise_error
    end
  end

  describe "#list_plans" do
    it "returns empty array when no plans" do
      expect(manager.list_plans).to eq([])
    end

    it "lists all plans" do
      manager.create_plan(name: "plan1", steps: ["Step 1"])
      manager.create_plan(name: "plan2", steps: ["Step 2"])

      plans = manager.list_plans
      expect(plans.length).to eq(2)
      expect(plans.map(&:name)).to contain_exactly("plan1", "plan2")
    end

    it "includes plans of all statuses" do
      manager.create_plan(name: "draft", steps: ["Step 1"])
      manager.create_plan(name: "active", steps: ["Step 2"])
      manager.activate_plan("active")

      plans = manager.list_plans
      expect(plans.length).to eq(2)
    end
  end

  describe "#get_active_plans" do
    it "returns only active plans" do
      manager.create_plan(name: "draft", steps: ["Step 1"])
      manager.create_plan(name: "active", steps: ["Step 2"])
      manager.activate_plan("active")
      manager.create_plan(name: "completed", steps: ["Step 3"])
      manager.activate_plan("completed")
      manager.mark_complete("completed")

      active_plans = manager.get_active_plans
      expect(active_plans.length).to eq(1)
      expect(active_plans.first.name).to eq("active")
    end

    it "returns empty array when no active plans" do
      manager.create_plan(name: "draft", steps: ["Step 1"])

      expect(manager.get_active_plans).to eq([])
    end
  end

  describe "#exists?" do
    it "returns true for existing plan" do
      manager.create_plan(name: "test", steps: ["Step 1"])

      expect(manager.exists?("test")).to be true
    end

    it "returns false for non-existent plan" do
      expect(manager.exists?("nonexistent")).to be false
    end
  end

  describe "error handling" do
    it "handles corrupted JSON gracefully" do
      manager # ensure directory exists
      file = plans_dir.join("corrupted.json")
      file.write("{ invalid json")

      plan = manager.get_plan("corrupted")
      expect(plan).to be_nil
    end
  end
end
