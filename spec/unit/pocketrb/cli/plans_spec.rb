# frozen_string_literal: true

RSpec.describe Pocketrb::CLI::Plans do
  let(:workspace) { Pathname.new(Dir.mktmpdir) }
  let(:cli) { described_class.new([], { workspace: workspace }) }
  let(:manager) { instance_double(Pocketrb::Planning::Manager) }

  before do
    allow(Pocketrb::Planning::Manager).to receive(:new).and_return(manager)
  end

  after do
    FileUtils.rm_rf(workspace)
  end

  describe "#call" do
    context "with no plans" do
      before do
        allow(manager).to receive(:list_plans).and_return([])
      end

      it "shows message when no plans exist" do
        output = capture_stdout { cli.call }

        expect(output).to include("No plans found")
      end
    end

    context "with plans" do
      let(:active_plan) do
        instance_double(
          Pocketrb::Planning::Plan,
          to_markdown: "# Plan 1\n\n- [ ] Step 1\n- [ ] Step 2"
        )
      end

      let(:partially_complete_plan) do
        instance_double(
          Pocketrb::Planning::Plan,
          to_markdown: "# Plan 2\n\n- [x] Step 1\n- [ ] Step 2"
        )
      end

      before do
        allow(manager).to receive(:list_plans).and_return([active_plan, partially_complete_plan])
      end

      it "lists all plans" do
        output = capture_stdout { cli.call }

        expect(output).to include("# Plan 1")
        expect(output).to include("# Plan 2")
      end

      it "shows plan steps" do
        output = capture_stdout { cli.call }

        expect(output).to include("Step 1")
        expect(output).to include("Step 2")
      end

      it "shows completed and pending steps" do
        output = capture_stdout { cli.call }

        expect(output).to include("[ ]")
        expect(output).to include("[x]")
      end
    end
  end

  private

  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end
end
