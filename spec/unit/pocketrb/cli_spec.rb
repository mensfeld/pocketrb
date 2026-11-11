# frozen_string_literal: true

RSpec.describe Pocketrb::CLI do
  describe "start --provider help" do
    it "lists every registered provider" do
      description = described_class.commands["start"].options[:provider].description

      expect(description).to include(*Pocketrb::Providers::Registry.available.map(&:to_s))
    end
  end
end
