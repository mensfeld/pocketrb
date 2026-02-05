# frozen_string_literal: true

RSpec.describe Pocketrb::Tools::Cron do
  let(:cron_service) { instance_double(Pocketrb::Cron::Service) }
  let(:context) do
    {
      cron_service: cron_service,
      default_channel: :telegram,
      default_chat_id: "12345"
    }
  end
  let(:tool) { described_class.new(context) }

  describe "#name" do
    it "returns cron" do
      expect(tool.name).to eq("cron")
    end
  end

  describe "#available?" do
    it "returns true when cron service is available" do
      expect(tool.available?).to be true
    end

    it "returns false when cron service is nil" do
      tool_without_cron = described_class.new({})
      expect(tool_without_cron.available?).to be false
    end
  end

  describe "#execute" do
    context "without cron service" do
      it "returns error" do
        tool_without_cron = described_class.new({})

        result = tool_without_cron.execute(action: "list")

        expect(result).to include("Error:")
        expect(result).to include("Cron service not available")
        expect(result).to include("--enable-cron")
      end
    end

    context "with add action" do
      let(:mock_job) do
        instance_double(
          Pocketrb::Cron::Job,
          id: "job_123",
          state: double(next_run_at_ms: Time.parse("2026-02-05 10:00:00").to_i * 1000)
        )
      end

      before do
        allow(cron_service).to receive(:add_job).and_return(mock_job)
      end

      it "creates a one-time job with 'at' schedule" do
        future_time = (Time.now + 3600).iso8601 # 1 hour from now
        result = tool.execute(
          action: "add",
          name: "Morning reminder",
          message: "Time to start work",
          schedule_type: "at",
          schedule_value: future_time
        )

        expect(result).to include("Created job 'Morning reminder'")
        expect(result).to include("job_123")
        expect(result).to include("Next run:")
        expect(cron_service).to have_received(:add_job)
      end

      it "creates a recurring job with 'every' schedule" do
        result = tool.execute(
          action: "add",
          name: "Hourly check",
          message: "Check status",
          schedule_type: "every",
          schedule_value: "3600"
        )

        expect(result).to include("Created job")
        expect(cron_service).to have_received(:add_job)
      end

      it "creates a cron expression job" do
        result = tool.execute(
          action: "add",
          name: "Daily at 9am",
          message: "Morning briefing",
          schedule_type: "cron",
          schedule_value: "0 9 * * *"
        )

        expect(result).to include("Created job")
      end

      it "requires name parameter" do
        result = tool.execute(
          action: "add",
          message: "Test",
          schedule_type: "every",
          schedule_value: "3600"
        )

        expect(result).to include("Error:")
        expect(result).to include("Name required")
      end

      it "requires message parameter" do
        result = tool.execute(
          action: "add",
          name: "Test",
          schedule_type: "every",
          schedule_value: "3600"
        )

        expect(result).to include("Error:")
        expect(result).to include("Message required")
      end

      it "requires schedule_type parameter" do
        result = tool.execute(
          action: "add",
          name: "Test",
          message: "Test message"
        )

        expect(result).to include("Error:")
        expect(result).to include("Schedule type required")
      end

      it "rejects past datetime for 'at' schedule" do
        result = tool.execute(
          action: "add",
          name: "Test",
          message: "Test",
          schedule_type: "at",
          schedule_value: "2020-01-01T00:00:00"
        )

        expect(result).to include("Error:")
        expect(result).to include("must be in the future")
      end

      it "rejects intervals less than 60 seconds" do
        result = tool.execute(
          action: "add",
          name: "Test",
          message: "Test",
          schedule_type: "every",
          schedule_value: "30"
        )

        expect(result).to include("Error:")
        expect(result).to include("at least 60 seconds")
      end

      it "validates datetime format for 'at' schedule" do
        result = tool.execute(
          action: "add",
          name: "Test",
          message: "Test",
          schedule_type: "at",
          schedule_value: "invalid-date"
        )

        expect(result).to include("Error:")
        expect(result).to include("Invalid datetime")
      end
    end

    context "with list action" do
      let(:enabled_job) do
        instance_double(
          Pocketrb::Cron::Job,
          id: "job_1",
          name: "Daily reminder",
          enabled: true,
          state: double(next_run_at_ms: Time.parse("2026-02-05 09:00:00").to_i * 1000),
          schedule: double(kind: :cron, expr: "0 9 * * *"),
          payload: double(message: "Good morning!")
        )
      end

      let(:disabled_job) do
        instance_double(
          Pocketrb::Cron::Job,
          id: "job_2",
          name: "Hourly check",
          enabled: false,
          state: double(next_run_at_ms: nil),
          schedule: double(kind: :every, every_ms: 3_600_000),
          payload: double(message: "Check status")
        )
      end

      it "lists enabled and disabled jobs" do
        allow(cron_service).to receive(:list_jobs).and_return([enabled_job, disabled_job])

        result = tool.execute(action: "list")

        expect(result).to include("Scheduled Jobs")
        expect(result).to include("job_1")
        expect(result).to include("Daily reminder")
        expect(result).to include("✓") # enabled
      end

      it "shows disabled status for disabled jobs" do
        allow(cron_service).to receive(:list_jobs).and_return([disabled_job])

        result = tool.execute(action: "list")

        expect(result).to include("job_2")
        expect(result).to include("✗") # disabled
      end

      it "shows message when no jobs exist" do
        allow(cron_service).to receive(:list_jobs).and_return([])

        result = tool.execute(action: "list")

        expect(result).to eq("No scheduled jobs.")
      end

      it "formats schedule descriptions correctly" do
        jobs = [
          instance_double(
            Pocketrb::Cron::Job,
            id: "job_1",
            name: "Test",
            enabled: true,
            state: double(next_run_at_ms: Time.now.to_i * 1000),
            schedule: double(kind: :every, every_ms: 86_400_000), # 1 day
            payload: double(message: "Test")
          )
        ]
        allow(cron_service).to receive(:list_jobs).and_return(jobs)

        result = tool.execute(action: "list")

        expect(result).to include("Every 1 day(s)")
      end
    end

    context "with remove action" do
      it "removes a job" do
        allow(cron_service).to receive(:remove_job).and_return(true)

        result = tool.execute(action: "remove", job_id: "job_123")

        expect(result).to include("Removed job: job_123")
        expect(cron_service).to have_received(:remove_job).with("job_123")
      end

      it "returns error when job not found" do
        allow(cron_service).to receive(:remove_job).and_return(false)

        result = tool.execute(action: "remove", job_id: "nonexistent")

        expect(result).to include("Error:")
        expect(result).to include("Job not found")
      end

      it "requires job_id parameter" do
        result = tool.execute(action: "remove")

        expect(result).to include("Error:")
        expect(result).to include("Job ID required")
      end
    end

    context "with enable action" do
      it "enables a job" do
        allow(cron_service).to receive(:enable_job).and_return(true)

        result = tool.execute(action: "enable", job_id: "job_123")

        expect(result).to include("Job job_123 enabled")
        expect(cron_service).to have_received(:enable_job).with("job_123", enabled: true)
      end

      it "requires job_id parameter" do
        result = tool.execute(action: "enable")

        expect(result).to include("Error:")
      end
    end

    context "with disable action" do
      it "disables a job" do
        allow(cron_service).to receive(:enable_job).and_return(true)

        result = tool.execute(action: "disable", job_id: "job_123")

        expect(result).to include("Job job_123 disabled")
        expect(cron_service).to have_received(:enable_job).with("job_123", enabled: false)
      end

      it "returns error when job not found" do
        allow(cron_service).to receive(:enable_job).and_return(false)

        result = tool.execute(action: "disable", job_id: "nonexistent")

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
