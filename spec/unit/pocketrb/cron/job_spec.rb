# frozen_string_literal: true

RSpec.describe Pocketrb::Cron do
  describe "Schedule" do
    describe "#initialize" do
      it "creates schedule with kind" do
        schedule = described_class::Schedule.new(kind: :at, at_ms: 1000)

        expect(schedule.kind).to eq(:at)
        expect(schedule.at_ms).to eq(1000)
      end

      it "defaults optional fields to nil" do
        schedule = described_class::Schedule.new(kind: :cron)

        expect(schedule.at_ms).to be_nil
        expect(schedule.every_ms).to be_nil
        expect(schedule.expr).to be_nil
        expect(schedule.tz).to be_nil
      end
    end

    describe "#one_time?" do
      it "returns true for :at schedules" do
        schedule = described_class::Schedule.new(kind: :at, at_ms: 1000)

        expect(schedule.one_time?).to be true
      end

      it "returns false for other schedules" do
        schedule = described_class::Schedule.new(kind: :every, every_ms: 3600)

        expect(schedule.one_time?).to be false
      end
    end

    describe "#interval?" do
      it "returns true for :every schedules" do
        schedule = described_class::Schedule.new(kind: :every, every_ms: 3600)

        expect(schedule.interval?).to be true
      end

      it "returns false for other schedules" do
        schedule = described_class::Schedule.new(kind: :at, at_ms: 1000)

        expect(schedule.interval?).to be false
      end
    end

    describe "#cron?" do
      it "returns true for :cron schedules" do
        schedule = described_class::Schedule.new(kind: :cron, expr: "0 9 * * *")

        expect(schedule.cron?).to be true
      end

      it "returns false for other schedules" do
        schedule = described_class::Schedule.new(kind: :at, at_ms: 1000)

        expect(schedule.cron?).to be false
      end
    end
  end

  describe "Payload" do
    describe "#initialize" do
      it "creates payload with message" do
        payload = described_class::Payload.new(message: "Test message")

        expect(payload.message).to eq("Test message")
      end

      it "defaults deliver to false" do
        payload = described_class::Payload.new(message: "Test")

        expect(payload.deliver).to be false
      end

      it "defaults channel to nil" do
        payload = described_class::Payload.new(message: "Test")

        expect(payload.channel).to be_nil
      end

      it "defaults to to nil" do
        payload = described_class::Payload.new(message: "Test")

        expect(payload.to).to be_nil
      end

      it "accepts optional fields" do
        payload = described_class::Payload.new(
          message: "Test",
          deliver: true,
          channel: :telegram,
          to: "chat_id"
        )

        expect(payload.deliver).to be true
        expect(payload.channel).to eq(:telegram)
        expect(payload.to).to eq("chat_id")
      end
    end
  end

  describe "JobState" do
    describe "#initialize" do
      it "creates state with default nil values" do
        state = described_class::JobState.new

        expect(state.next_run_at_ms).to be_nil
        expect(state.last_run_at_ms).to be_nil
        expect(state.last_status).to be_nil
        expect(state.last_error).to be_nil
      end

      it "accepts all optional fields" do
        state = described_class::JobState.new(
          next_run_at_ms: 1000,
          last_run_at_ms: 900,
          last_status: "success",
          last_error: "error message"
        )

        expect(state.next_run_at_ms).to eq(1000)
        expect(state.last_run_at_ms).to eq(900)
        expect(state.last_status).to eq("success")
        expect(state.last_error).to eq("error message")
      end
    end
  end

  describe "Job" do
    let(:schedule) do
      described_class::Schedule.new(
        kind: :every,
        every_ms: 3600_000
      )
    end

    let(:payload) do
      described_class::Payload.new(
        message: "Test message",
        deliver: true,
        channel: :telegram,
        to: "chat123"
      )
    end

    let(:job) do
      described_class::Job.new(
        id: "job_123",
        name: "Test job",
        schedule: schedule,
        payload: payload
      )
    end

    describe "#initialize" do
      it "creates job with required fields" do
        expect(job.id).to eq("job_123")
        expect(job.name).to eq("Test job")
        expect(job.schedule).to eq(schedule)
        expect(job.payload).to eq(payload)
      end

      it "defaults enabled to true" do
        expect(job.enabled).to be true
      end

      it "defaults state to empty JobState" do
        expect(job.state).to be_a(described_class::JobState)
      end

      it "defaults delete_after_run to false" do
        expect(job.delete_after_run).to be false
      end

      it "sets created_at_ms to current time" do
        expect(job.created_at_ms).to be_a(Integer)
        expect(job.created_at_ms).to be > 0
      end

      it "sets updated_at_ms to current time" do
        expect(job.updated_at_ms).to be_a(Integer)
        expect(job.updated_at_ms).to be > 0
      end

      it "accepts custom timestamps" do
        j = described_class::Job.new(
          id: "job",
          name: "Test",
          schedule: schedule,
          payload: payload,
          created_at_ms: 1000,
          updated_at_ms: 2000
        )

        expect(j.created_at_ms).to eq(1000)
        expect(j.updated_at_ms).to eq(2000)
      end

      it "accepts enabled flag" do
        j = described_class::Job.new(
          id: "job",
          name: "Test",
          schedule: schedule,
          payload: payload,
          enabled: false
        )

        expect(j.enabled).to be false
      end

      it "accepts delete_after_run flag" do
        j = described_class::Job.new(
          id: "job",
          name: "Test",
          schedule: schedule,
          payload: payload,
          delete_after_run: true
        )

        expect(j.delete_after_run).to be true
      end
    end

    describe "#due?" do
      let(:state_with_next_run) do
        described_class::JobState.new(next_run_at_ms: 1000)
      end

      let(:job_with_next_run) do
        described_class::Job.new(
          id: "job",
          name: "Test",
          schedule: schedule,
          payload: payload,
          state: state_with_next_run
        )
      end

      it "returns false when disabled" do
        j = described_class::Job.new(
          id: "job",
          name: "Test",
          schedule: schedule,
          payload: payload,
          enabled: false,
          state: state_with_next_run
        )

        expect(j.due?(2000)).to be false
      end

      it "returns false when next_run_at_ms is nil" do
        expect(job.due?).to be false
      end

      it "returns true when next_run_at_ms is in the past" do
        expect(job_with_next_run.due?(2000)).to be true
      end

      it "returns true when next_run_at_ms equals current time" do
        expect(job_with_next_run.due?(1000)).to be true
      end

      it "returns false when next_run_at_ms is in the future" do
        expect(job_with_next_run.due?(500)).to be false
      end

      it "uses current time when now_ms not provided" do
        current_ms = (Time.now.to_f * 1000).to_i
        past_state = described_class::JobState.new(next_run_at_ms: current_ms - 1000)
        past_job = described_class::Job.new(
          id: "job",
          name: "Test",
          schedule: schedule,
          payload: payload,
          state: past_state
        )

        expect(past_job.due?).to be true
      end
    end

    describe "#to_h" do
      it "converts to hash" do
        hash = job.to_h

        expect(hash["id"]).to eq("job_123")
        expect(hash["name"]).to eq("Test job")
        expect(hash["enabled"]).to be true
      end

      it "includes schedule details" do
        hash = job.to_h

        expect(hash["schedule"]["kind"]).to eq("every")
        expect(hash["schedule"]["every_ms"]).to eq(3600_000)
      end

      it "includes payload details" do
        hash = job.to_h

        expect(hash["payload"]["message"]).to eq("Test message")
        expect(hash["payload"]["deliver"]).to be true
        expect(hash["payload"]["channel"]).to eq(:telegram)
        expect(hash["payload"]["to"]).to eq("chat123")
      end

      it "includes state details" do
        hash = job.to_h

        expect(hash["state"]["next_run_at_ms"]).to be_nil
        expect(hash["state"]["last_run_at_ms"]).to be_nil
        expect(hash["state"]["last_status"]).to be_nil
        expect(hash["state"]["last_error"]).to be_nil
      end

      it "includes timestamps" do
        hash = job.to_h

        expect(hash["created_at_ms"]).to be_a(Integer)
        expect(hash["updated_at_ms"]).to be_a(Integer)
      end

      it "includes delete_after_run flag" do
        hash = job.to_h

        expect(hash["delete_after_run"]).to be false
      end
    end

    describe ".from_h" do
      let(:hash) do
        {
          "id" => "job_456",
          "name" => "Restored job",
          "enabled" => false,
          "schedule" => {
            "kind" => "at",
            "at_ms" => 5000,
            "every_ms" => nil,
            "expr" => nil,
            "tz" => nil
          },
          "payload" => {
            "message" => "Restored message",
            "deliver" => false,
            "channel" => nil,
            "to" => nil
          },
          "state" => {
            "next_run_at_ms" => 6000,
            "last_run_at_ms" => 4000,
            "last_status" => "completed",
            "last_error" => nil
          },
          "created_at_ms" => 1000,
          "updated_at_ms" => 2000,
          "delete_after_run" => true
        }
      end

      it "creates job from hash" do
        j = described_class::Job.from_h(hash)

        expect(j.id).to eq("job_456")
        expect(j.name).to eq("Restored job")
        expect(j.enabled).to be false
        expect(j.delete_after_run).to be true
      end

      it "restores schedule" do
        j = described_class::Job.from_h(hash)

        expect(j.schedule.kind).to eq(:at)
        expect(j.schedule.at_ms).to eq(5000)
      end

      it "restores payload" do
        j = described_class::Job.from_h(hash)

        expect(j.payload.message).to eq("Restored message")
        expect(j.payload.deliver).to be false
      end

      it "restores state" do
        j = described_class::Job.from_h(hash)

        expect(j.state.next_run_at_ms).to eq(6000)
        expect(j.state.last_run_at_ms).to eq(4000)
        expect(j.state.last_status).to eq("completed")
      end

      it "restores timestamps" do
        j = described_class::Job.from_h(hash)

        expect(j.created_at_ms).to eq(1000)
        expect(j.updated_at_ms).to eq(2000)
      end

      it "handles missing state in hash" do
        hash_without_state = hash.dup
        hash_without_state.delete("state")

        j = described_class::Job.from_h(hash_without_state)

        expect(j.state).to be_a(described_class::JobState)
        expect(j.state.next_run_at_ms).to be_nil
      end
    end
  end
end
