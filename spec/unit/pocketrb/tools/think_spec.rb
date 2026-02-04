# frozen_string_literal: true

RSpec.describe Pocketrb::Tools::Think do
  let(:tool) { described_class.new }

  describe "#name" do
    it "returns think" do
      expect(tool.name).to eq("think")
    end
  end

  describe "#description" do
    it "explains the tool purpose" do
      expect(tool.description).to include("think through complex problems")
      expect(tool.description).to include("not shown to the user")
    end
  end

  describe "#parameters" do
    it "requires thought parameter" do
      params = tool.parameters
      expect(params[:properties]).to have_key(:thought)
      expect(params[:required]).to include("thought")
    end
  end

  describe "#execute" do
    it "records the thought" do
      result = tool.execute(thought: "Analyzing the problem...")

      expect(result).to eq("Thought recorded.")
    end

    it "logs the thought for debugging" do
      allow(Pocketrb.logger).to receive(:debug)

      tool.execute(thought: "Complex reasoning here")

      expect(Pocketrb.logger).to have_received(:debug)
        .with(/Agent thought:.*Complex reasoning/)
    end

    it "handles long thoughts" do
      long_thought = "x" * 500

      result = tool.execute(thought: long_thought)

      expect(result).to eq("Thought recorded.")
    end

    it "handles multiline thoughts" do
      thought = <<~THOUGHT
        Step 1: Analyze requirements
        Step 2: Plan approach
        Step 3: Execute
      THOUGHT

      result = tool.execute(thought: thought)

      expect(result).to eq("Thought recorded.")
    end
  end
end
