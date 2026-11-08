# frozen_string_literal: true

require "tmpdir"

RSpec.describe Pocketrb::Cron::Service do
  let(:store_dir) { Dir.mktmpdir }
  let(:service) { described_class.new(store_path: File.join(store_dir, "jobs.json"), on_job: ->(_job) {}) }

  after { FileUtils.rm_rf(store_dir) }

  describe "#add_cron_job" do
    it "schedules the next run from the cron expression" do
      job = service.add_cron_job(name: "daily", cron: "0 9 * * *", message: "Report")
      next_run = Time.at(job.state.next_run_at_ms / 1000.0)

      expect([next_run.hour, next_run.min, next_run.sec]).to eq([9, 0, 0])
      expect(next_run).to be_between(Time.now, Time.now + 86_400)
    end

    it "leaves the next run unset for an invalid cron expression" do
      job = service.add_cron_job(name: "broken", cron: "not a cron", message: "Report")

      expect(job.state.next_run_at_ms).to be_nil
    end
  end
end
