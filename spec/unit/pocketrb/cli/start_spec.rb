# frozen_string_literal: true

RSpec.describe Pocketrb::CLI::Start do
  describe "--provider help" do
    it "lists every registered provider" do
      description = described_class.commands["call"].options[:provider].description

      expect(description).to include(*Pocketrb::Providers::Registry.new.available.map(&:to_s))
    end
  end
end
