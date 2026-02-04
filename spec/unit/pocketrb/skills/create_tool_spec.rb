# frozen_string_literal: true

RSpec.describe Pocketrb::Skills::CreateTool do
  let(:workspace) { Pathname.new(Dir.mktmpdir) }
  let(:tool) { described_class.new(workspace: workspace) }

  before do
    FileUtils.mkdir_p(workspace.join("skills"))
  end

  after do
    FileUtils.rm_rf(workspace)
  end

  describe "#name" do
    it "returns skill_create" do
      expect(tool.name).to eq("skill_create")
    end
  end

  describe "#execute" do
    context "with valid skill" do
      it "creates skill directory and file" do
        result = tool.execute(
          skill_name: "test-skill",
          skill_description: "A test skill",
          content: "Test instructions"
        )

        expect(result).to include("Created skill")
        expect(workspace.join("skills/test-skill/SKILL.md")).to exist
      end

      it "creates SKILL.md with frontmatter" do
        tool.execute(
          skill_name: "demo",
          skill_description: "Demo skill",
          content: "Demo content"
        )

        skill_file = workspace.join("skills/demo/SKILL.md")
        content = File.read(skill_file)

        expect(content).to include("---")
        expect(content).to include("name: demo")
        expect(content).to include("description: Demo skill")
        expect(content).to include("Demo content")
      end

      it "includes triggers in frontmatter when provided" do
        tool.execute(
          skill_name: "with-triggers",
          skill_description: "Skill with triggers",
          content: "Content",
          triggers: %w[keyword1 keyword2]
        )

        content = File.read(workspace.join("skills/with-triggers/SKILL.md"))

        expect(content).to include("triggers:")
        expect(content).to include("- keyword1")
        expect(content).to include("- keyword2")
      end

      it "includes always flag when true" do
        tool.execute(
          skill_name: "always-loaded",
          skill_description: "Always loaded skill",
          content: "Content",
          always: true
        )

        content = File.read(workspace.join("skills/always-loaded/SKILL.md"))

        expect(content).to include("always: true")
      end

      it "updates TOOLS.md when it exists" do
        tools_file = workspace.join("TOOLS.md")
        File.write(tools_file, "# Tools\n\n## Skills\n\n")

        tool.execute(
          skill_name: "documented-skill",
          skill_description: "A documented skill",
          content: "Content"
        )

        tools_content = File.read(tools_file)
        expect(tools_content).to include("documented-skill")
        expect(tools_content).to include("A documented skill")
      end
    end

    context "with invalid skill name" do
      it "rejects names with uppercase letters" do
        result = tool.execute(
          skill_name: "InvalidName",
          skill_description: "Test",
          content: "Content"
        )

        expect(result).to include("Error:")
        expect(result).to include("Invalid skill name")
      end

      it "rejects names with spaces" do
        result = tool.execute(
          skill_name: "invalid name",
          skill_description: "Test",
          content: "Content"
        )

        expect(result).to include("Error:")
      end

      it "rejects names with special characters" do
        result = tool.execute(
          skill_name: "invalid@skill",
          skill_description: "Test",
          content: "Content"
        )

        expect(result).to include("Error:")
      end

      it "accepts valid names with hyphens" do
        result = tool.execute(
          skill_name: "valid-skill-name",
          skill_description: "Test",
          content: "Content"
        )

        expect(result).to include("Created skill")
      end

      it "accepts valid names with numbers" do
        result = tool.execute(
          skill_name: "skill123",
          skill_description: "Test",
          content: "Content"
        )

        expect(result).to include("Created skill")
      end
    end

    context "with existing skill" do
      it "returns error instead of overwriting" do
        # Create skill first time
        tool.execute(
          skill_name: "existing",
          skill_description: "First",
          content: "Original"
        )

        # Try to create again
        result = tool.execute(
          skill_name: "existing",
          skill_description: "Second",
          content: "New"
        )

        expect(result).to include("Error:")
        expect(result).to include("already exists")
        expect(result).to include("skill_modify")
      end
    end

    context "without TOOLS.md" do
      it "creates skill successfully without updating docs" do
        result = tool.execute(
          skill_name: "no-docs",
          skill_description: "Test",
          content: "Content"
        )

        expect(result).to include("Created skill")
        expect(workspace.join("skills/no-docs/SKILL.md")).to exist
      end
    end

    context "with empty triggers array" do
      it "does not include triggers in frontmatter" do
        tool.execute(
          skill_name: "no-triggers",
          skill_description: "Test",
          content: "Content",
          triggers: []
        )

        content = File.read(workspace.join("skills/no-triggers/SKILL.md"))

        expect(content).not_to include("triggers:")
      end
    end
  end
end
