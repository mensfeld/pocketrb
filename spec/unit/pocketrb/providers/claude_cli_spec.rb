# frozen_string_literal: true

RSpec.describe Pocketrb::Providers::ClaudeCLI do
  # Skips #initialize, which requires the claude binary on PATH
  subject(:provider) { described_class.allocate }

  describe "response model" do
    it "maps the sonnet alias to the current model ID" do
      response = provider.send(:parse_cli_response, { content: "Hi", usage: {} }, "sonnet")

      expect(response.model).to eq("claude-sonnet-5-5")
    end

    it "keeps an unknown model name as is" do
      response = provider.send(:parse_cli_response, { content: "Hi", usage: {} }, "custom-model")

      expect(response.model).to eq("custom-model")
    end
  end
end
