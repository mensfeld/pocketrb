# frozen_string_literal: true

RSpec.describe Pocketrb::Planning::Tool do
  let(:workspace) { Pathname.new(Dir.mktmpdir) }
  let(:tool) { described_class.new(workspace: workspace) }
  let(:manager) { instance_double(Pocketrb::Planning::Manager) }
  let(:mock_plan) do
    instance_double(
      Pocketrb::Planning::Plan,
      name: "test-plan",
      status: "active",
      progress: 50,
      complete?: false,
      next_step: double(index: 1, description: "Next step"),
      to_markdown: "# Test Plan\n\n- [x] Step 1\n- [ ] Step 2"
    )
  end

  before do
    allow(Pocketrb::Planning::Manager).to receive(:new).and_return(manager)
  end

  after do
    FileUtils.rm_rf(workspace)
  end

  describe "#name" do
    it "returns plan" do
      expect(tool.name).to eq("plan")
    end
  end

  describe "#execute" do
    context "with create action" do
      it "creates and activates a plan" do
        allow(manager).to receive(:create_plan).and_return(mock_plan)
        allow(mock_plan).to receive(:activate!)
        allow(manager).to receive(:update_plan)

        result = tool.execute(
          action: "create",
          plan_name: "test-plan",
          plan_description: "Test description",
          steps: ["Step 1", "Step 2"]
        )

        expect(result).to include("Created and activated")
        expect(result).to include("test-plan")
        expect(manager).to have_received(:create_plan)
        expect(mock_plan).to have_received(:activate!)
      end

      it "requires plan name" do
        result = tool.execute(action: "create", steps: ["Step 1"])

        expect(result).to include("Error:")
        expect(result).to include("Plan name is required")
      end

      it "requires at least one step" do
        result = tool.execute(action: "create", plan_name: "test", steps: [])

        expect(result).to include("Error:")
        expect(result).to include("At least one step is required")
      end
    end

    context "with update action" do
      it "updates plan with new steps" do
        allow(manager).to receive(:update_plan).and_return(mock_plan)

        result = tool.execute(
          action: "update",
          plan_name: "test-plan",
          steps: ["New step"]
        )

        expect(result).to include("Updated plan")
        expect(manager).to have_received(:update_plan)
      end

      it "requires plan name" do
        result = tool.execute(action: "update", steps: ["Step"])

        expect(result).to include("Error:")
        expect(result).to include("Plan name is required")
      end
    end

    context "with complete action" do
      it "completes a step and shows next step" do
        allow(manager).to receive(:update_plan).and_return(mock_plan)

        result = tool.execute(
          action: "complete",
          plan_name: "test-plan",
          step_index: 0,
          notes: "Done"
        )

        expect(result).to include("Completed step 1")
        expect(result).to include("Next: Step 2")
      end

      it "shows completion message when plan is complete" do
        complete_plan = instance_double(
          Pocketrb::Planning::Plan,
          complete?: true,
          to_markdown: "# Complete"
        )
        allow(manager).to receive(:update_plan).and_return(complete_plan)

        result = tool.execute(
          action: "complete",
          plan_name: "test-plan",
          step_index: 1
        )

        expect(result).to include("Plan 'test-plan' is now complete")
      end

      it "requires plan name" do
        result = tool.execute(action: "complete", step_index: 0)

        expect(result).to include("Error:")
        expect(result).to include("Plan name is required")
      end

      it "requires step index" do
        result = tool.execute(action: "complete", plan_name: "test")

        expect(result).to include("Error:")
        expect(result).to include("Step index is required")
      end
    end

    context "with fail action" do
      it "marks step as failed" do
        allow(manager).to receive(:fail_step).and_return(mock_plan)

        result = tool.execute(
          action: "fail",
          plan_name: "test-plan",
          step_index: 0,
          notes: "Failed because..."
        )

        expect(result).to include("Marked step 1 as failed")
        expect(manager).to have_received(:fail_step)
      end

      it "requires plan name" do
        result = tool.execute(action: "fail", step_index: 0)

        expect(result).to include("Error:")
      end

      it "requires step index" do
        result = tool.execute(action: "fail", plan_name: "test")

        expect(result).to include("Error:")
      end
    end

    context "with list action" do
      it "lists all plans" do
        plans = [
          instance_double(
            Pocketrb::Planning::Plan,
            name: "plan1",
            status: "active",
            progress: 25
          ),
          instance_double(
            Pocketrb::Planning::Plan,
            name: "plan2",
            status: "completed",
            progress: 100
          )
        ]
        allow(manager).to receive(:list_plans).and_return(plans)

        result = tool.execute(action: "list")

        expect(result).to include("plan1")
        expect(result).to include("plan2")
        expect(result).to include("25%")
        expect(result).to include("100%")
      end

      it "shows message when no plans exist" do
        allow(manager).to receive(:list_plans).and_return([])

        result = tool.execute(action: "list")

        expect(result).to eq("No plans found")
      end
    end

    context "with show action" do
      it "shows plan details" do
        allow(manager).to receive(:get_plan).and_return(mock_plan)

        result = tool.execute(action: "show", plan_name: "test-plan")

        expect(result).to include("# Test Plan")
        expect(manager).to have_received(:get_plan).with("test-plan")
      end

      it "returns error when plan not found" do
        allow(manager).to receive(:get_plan).and_return(nil)

        result = tool.execute(action: "show", plan_name: "nonexistent")

        expect(result).to include("Error:")
        expect(result).to include("not found")
      end

      it "requires plan name" do
        result = tool.execute(action: "show")

        expect(result).to include("Error:")
        expect(result).to include("Plan name is required")
      end
    end

    context "with delete action" do
      it "deletes a plan" do
        allow(manager).to receive(:delete_plan)

        result = tool.execute(action: "delete", plan_name: "test-plan")

        expect(result).to include("Deleted plan")
        expect(manager).to have_received(:delete_plan).with("test-plan")
      end

      it "requires plan name" do
        result = tool.execute(action: "delete")

        expect(result).to include("Error:")
      end
    end

    context "with unknown action" do
      it "returns error" do
        result = tool.execute(action: "invalid")

        expect(result).to include("Error:")
        expect(result).to include("Unknown action")
      end
    end
  end
end
