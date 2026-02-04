# frozen_string_literal: true

RSpec.describe Pocketrb::CLI::Version do
  describe "#call" do
    it "displays the current version" do
      expect { described_class.start(["call"]) }.to output(/Pocketrb #{Pocketrb::VERSION}/o).to_stdout
    end
  end
end
