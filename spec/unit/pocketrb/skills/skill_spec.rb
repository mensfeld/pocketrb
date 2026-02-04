# frozen_string_literal: true

require "tempfile"

RSpec.describe Pocketrb::Skills::Skill do
  let(:skill) do
    described_class.new(
      name: "test-skill",
      description: "A test skill",
      content: "This is the skill content",
      path: Pathname.new("/path/to/skill.md"),
      metadata: {
        triggers: %w[test example],
        always: false
      }
    )
  end

  describe "#initialize" do
    it "sets name" do
      expect(skill.name).to eq("test-skill")
    end

    it "sets description" do
      expect(skill.description).to eq("A test skill")
    end

    it "sets content" do
      expect(skill.content).to eq("This is the skill content")
    end

    it "sets path" do
      expect(skill.path).to eq(Pathname.new("/path/to/skill.md"))
    end

    it "sets metadata" do
      expect(skill.metadata).to eq({ triggers: %w[test example], always: false })
    end

    it "defaults metadata to empty hash" do
      s = described_class.new(
        name: "skill",
        description: "desc",
        content: "content",
        path: Pathname.new("/path")
      )

      expect(s.metadata).to eq({})
    end
  end

  describe "#always?" do
    it "returns true when always metadata is true" do
      s = described_class.new(
        name: "skill",
        description: "desc",
        content: "content",
        path: Pathname.new("/path"),
        metadata: { always: true }
      )

      expect(s.always?).to be true
    end

    it "returns true when always metadata is string 'true'" do
      s = described_class.new(
        name: "skill",
        description: "desc",
        content: "content",
        path: Pathname.new("/path"),
        metadata: { "always" => true }
      )

      expect(s.always?).to be true
    end

    it "returns false when always metadata is false" do
      expect(skill.always?).to be false
    end

    it "returns false when always metadata is missing" do
      s = described_class.new(
        name: "skill",
        description: "desc",
        content: "content",
        path: Pathname.new("/path"),
        metadata: {}
      )

      expect(s.always?).to be false
    end
  end

  describe "#available?" do
    it "returns true when no requirements" do
      expect(skill.available?).to be true
    end

    it "returns true when env requirement is met" do
      ENV["TEST_VAR"] = "value"

      s = described_class.new(
        name: "skill",
        description: "desc",
        content: "content",
        path: Pathname.new("/path"),
        metadata: { requires: "env:TEST_VAR" }
      )

      expect(s.available?).to be true

      ENV.delete("TEST_VAR")
    end

    it "returns false when env requirement is not met" do
      ENV.delete("MISSING_VAR")

      s = described_class.new(
        name: "skill",
        description: "desc",
        content: "content",
        path: Pathname.new("/path"),
        metadata: { requires: "env:MISSING_VAR" }
      )

      expect(s.available?).to be false
    end

    it "returns true when file requirement is met" do
      file = Tempfile.new("test")

      s = described_class.new(
        name: "skill",
        description: "desc",
        content: "content",
        path: Pathname.new("/path"),
        metadata: { requires: "file:#{file.path}" }
      )

      expect(s.available?).to be true

      file.close
      file.unlink
    end

    it "returns false when file requirement is not met" do
      s = described_class.new(
        name: "skill",
        description: "desc",
        content: "content",
        path: Pathname.new("/path"),
        metadata: { requires: "file:/nonexistent/file" }
      )

      expect(s.available?).to be false
    end

    it "returns true when all requirements are met" do
      ENV["TEST_VAR"] = "value"
      file = Tempfile.new("test")

      s = described_class.new(
        name: "skill",
        description: "desc",
        content: "content",
        path: Pathname.new("/path"),
        metadata: { requires: ["env:TEST_VAR", "file:#{file.path}"] }
      )

      expect(s.available?).to be true

      ENV.delete("TEST_VAR")
      file.close
      file.unlink
    end

    it "returns false when any requirement is not met" do
      ENV["TEST_VAR"] = "value"

      s = described_class.new(
        name: "skill",
        description: "desc",
        content: "content",
        path: Pathname.new("/path"),
        metadata: { requires: ["env:TEST_VAR", "file:/nonexistent"] }
      )

      expect(s.available?).to be false

      ENV.delete("TEST_VAR")
    end

    it "returns true for tool requirements" do
      s = described_class.new(
        name: "skill",
        description: "desc",
        content: "content",
        path: Pathname.new("/path"),
        metadata: { requires: "tool:some_tool" }
      )

      expect(s.available?).to be true
    end

    it "handles string keys in metadata" do
      s = described_class.new(
        name: "skill",
        description: "desc",
        content: "content",
        path: Pathname.new("/path"),
        metadata: { "requires" => "env:MISSING" }
      )

      expect(s.available?).to be false
    end
  end

  describe "#triggers" do
    it "returns triggers from metadata" do
      expect(skill.triggers).to eq(%w[test example])
    end

    it "returns empty array when no triggers" do
      s = described_class.new(
        name: "skill",
        description: "desc",
        content: "content",
        path: Pathname.new("/path"),
        metadata: {}
      )

      expect(s.triggers).to eq([])
    end

    it "handles string keys in metadata" do
      s = described_class.new(
        name: "skill",
        description: "desc",
        content: "content",
        path: Pathname.new("/path"),
        metadata: { "triggers" => %w[keyword1 keyword2] }
      )

      expect(s.triggers).to eq(%w[keyword1 keyword2])
    end

    it "converts single trigger to array" do
      s = described_class.new(
        name: "skill",
        description: "desc",
        content: "content",
        path: Pathname.new("/path"),
        metadata: { triggers: "single-trigger" }
      )

      expect(s.triggers).to eq(["single-trigger"])
    end
  end

  describe "#matches?" do
    it "returns false when no triggers" do
      s = described_class.new(
        name: "skill",
        description: "desc",
        content: "content",
        path: Pathname.new("/path"),
        metadata: {}
      )

      expect(s.matches?("test message")).to be false
    end

    it "returns true when text contains trigger" do
      expect(skill.matches?("This is a test message")).to be true
    end

    it "returns true when text contains any trigger" do
      expect(skill.matches?("Here is an example")).to be true
    end

    it "returns false when text does not contain any trigger" do
      expect(skill.matches?("Something else")).to be false
    end

    it "is case insensitive" do
      expect(skill.matches?("This is a TEST message")).to be true
      expect(skill.matches?("Here is an EXAMPLE")).to be true
    end

    it "matches partial words" do
      s = described_class.new(
        name: "skill",
        description: "desc",
        content: "content",
        path: Pathname.new("/path"),
        metadata: { triggers: ["git"] }
      )

      expect(s.matches?("github issue")).to be true
    end
  end

  describe "#to_prompt" do
    it "wraps content in skill XML tags" do
      prompt = skill.to_prompt

      expect(prompt).to include('<skill name="test-skill">')
      expect(prompt).to include("This is the skill content")
      expect(prompt).to include("</skill>")
    end

    it "includes skill name in tag" do
      expect(skill.to_prompt).to include('name="test-skill"')
    end
  end

  describe "#to_summary" do
    it "returns name and description" do
      summary = skill.to_summary

      expect(summary).to eq("- test-skill: A test skill")
    end
  end
end
