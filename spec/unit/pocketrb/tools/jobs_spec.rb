# frozen_string_literal: true

RSpec.describe Pocketrb::Tools::Jobs do
  let(:workspace) { Pathname.new(Dir.mktmpdir) }
  let(:tool) { described_class.new(workspace: workspace) }
  let(:job_manager) { instance_double(Pocketrb::Tools::BackgroundJobManager) }

  before do
    allow(Pocketrb::Tools::BackgroundJobManager).to receive(:new).and_return(job_manager)
  end

  after do
    FileUtils.rm_rf(workspace)
  end

  describe "#name" do
    it "returns jobs" do
      expect(tool.name).to eq("jobs")
    end
  end

  describe "#execute" do
    context "with list action" do
      it "lists all jobs grouped by status" do
        jobs = [
          { job_id: "job_1", name: "Running task", running: true, pid: 1234 },
          { job_id: "job_2", name: "Completed task", running: false }
        ]
        allow(job_manager).to receive(:list).and_return(jobs)

        result = tool.execute(action: "list")

        expect(result).to include("RUNNING:")
        expect(result).to include("job_1")
        expect(result).to include("PID 1234")
        expect(result).to include("COMPLETED:")
        expect(result).to include("job_2")
      end

      it "shows message when no jobs exist" do
        allow(job_manager).to receive(:list).and_return([])

        result = tool.execute(action: "list")

        expect(result).to eq("No background jobs found.")
      end

      it "limits completed jobs to 10" do
        jobs = (1..15).map do |i|
          { job_id: "job_#{i}", name: "Task #{i}", running: false }
        end
        allow(job_manager).to receive(:list).and_return(jobs)

        result = tool.execute(action: "list")

        expect(result).to include("... and 5 more")
      end

      it "shows all running jobs without limit" do
        jobs = (1..15).map do |i|
          { job_id: "job_#{i}", name: "Task #{i}", running: true, pid: 1000 + i }
        end
        allow(job_manager).to receive(:list).and_return(jobs)

        result = tool.execute(action: "list")

        # All 15 running jobs should be shown
        (1..15).each do |i|
          expect(result).to include("job_#{i}")
        end
      end
    end

    context "with status action" do
      let(:job_status) do
        {
          job_id: "job_123",
          name: "Test job",
          running: true,
          pid: 5678,
          command: "sleep 100",
          output: "Line 1\nLine 2\nLine 3\n"
        }
      end

      it "shows detailed job status" do
        allow(job_manager).to receive(:status).and_return(job_status)

        result = tool.execute(action: "status", job_id: "job_123")

        expect(result).to include("Job: job_123")
        expect(result).to include("Name: Test job")
        expect(result).to include("Status: RUNNING")
        expect(result).to include("PID: 5678")
        expect(result).to include("Command: sleep 100")
        expect(result).to include("Recent output:")
      end

      it "shows COMPLETED status for finished jobs" do
        completed_status = job_status.merge(running: false)
        allow(job_manager).to receive(:status).and_return(completed_status)

        result = tool.execute(action: "status", job_id: "job_123")

        expect(result).to include("Status: COMPLETED")
      end

      it "returns error when job not found" do
        allow(job_manager).to receive(:status).and_return(nil)

        result = tool.execute(action: "status", job_id: "nonexistent")

        expect(result).to include("Error:")
        expect(result).to include("Job not found")
      end

      it "requires job_id parameter" do
        result = tool.execute(action: "status")

        expect(result).to include("Error:")
        expect(result).to include("Job ID required")
      end
    end

    context "with output action" do
      it "shows job output" do
        output_text = "Output line 1\nOutput line 2\n"
        allow(job_manager).to receive(:output).and_return(output_text)

        result = tool.execute(action: "output", job_id: "job_123", lines: 50)

        expect(result).to include("Output (last 50 lines)")
        expect(result).to include("Output line 1")
        expect(result).to include("Output line 2")
        expect(job_manager).to have_received(:output).with("job_123", lines: 50)
      end

      it "uses default of 50 lines when not specified" do
        allow(job_manager).to receive(:output).and_return("Output")

        tool.execute(action: "output", job_id: "job_123")

        expect(job_manager).to have_received(:output).with("job_123", lines: 50)
      end

      it "accepts custom line count" do
        allow(job_manager).to receive(:output).and_return("Output")

        tool.execute(action: "output", job_id: "job_123", lines: 100)

        expect(job_manager).to have_received(:output).with("job_123", lines: 100)
      end

      it "returns error when job not found" do
        allow(job_manager).to receive(:output).and_return(nil)

        result = tool.execute(action: "output", job_id: "nonexistent")

        expect(result).to include("Error:")
        expect(result).to include("Job not found")
      end

      it "requires job_id parameter" do
        result = tool.execute(action: "output")

        expect(result).to include("Error:")
        expect(result).to include("Job ID required")
      end
    end

    context "with kill action" do
      it "kills a running job" do
        allow(job_manager).to receive(:kill).and_return(true)

        result = tool.execute(action: "kill", job_id: "job_123")

        expect(result).to include("Killed job: job_123")
        expect(job_manager).to have_received(:kill).with("job_123")
      end

      it "returns error when job cannot be killed" do
        allow(job_manager).to receive(:kill).and_return(false)

        result = tool.execute(action: "kill", job_id: "job_123")

        expect(result).to include("Error:")
        expect(result).to include("Could not kill job")
        expect(result).to include("may not be running")
      end

      it "requires job_id parameter" do
        result = tool.execute(action: "kill")

        expect(result).to include("Error:")
        expect(result).to include("Job ID required")
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
