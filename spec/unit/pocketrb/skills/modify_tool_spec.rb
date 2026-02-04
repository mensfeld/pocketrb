# frozen_string_literal: true

RSpec.describe Pocketrb::Skills::ModifyTool do
  let(:workspace) { Pathname.new(Dir.mktmpdir) }
  let(:tool) { described_class.new(workspace: workspace) }
  let(:skill_dir) { workspace.join("skills/test-skill") }
  let(:skill_file) { skill_dir.join("SKILL.md") }

  before do
    FileUtils.mkdir_p(skill_dir)
    File.write(skill_file, <<~MD)
      ---
      name: test-skill
      description: Original description
      triggers:
      - keyword1
      - keyword2
      ---

      Original skill content
    MD
  end

  after do
    FileUtils.rm_rf(workspace)
  end

  describe "#name" do
    it "returns skill_modify" do
      expect(tool.name).to eq("skill_modify")
    end
  end

  describe "#execute" do
    context "with non-existent skill" do
      it "returns error" do
        result = tool.execute(skill_name: "nonexistent")

        expect(result).to include("Error:")
        expect(result).to include("not found")
      end
    end

    context "with new_content" do
      it "replaces skill content completely" do
        result = tool.execute(
          skill_name: "test-skill",
          new_content: "Completely new content"
        )

        expect(result).to include("Modified skill")
        updated = File.read(skill_file)
        expect(updated).to include("Completely new content")
        expect(updated).not_to include("Original skill content")
      end

      it "preserves frontmatter metadata" do
        tool.execute(
          skill_name: "test-skill",
          new_content: "New content"
        )

        updated = File.read(skill_file)
        expect(updated).to include("name: test-skill")
        expect(updated).to include("description: Original description")
      end
    end

    context "with append_content" do
      it "appends to existing content" do
        result = tool.execute(
          skill_name: "test-skill",
          append_content: "Additional instructions"
        )

        expect(result).to include("Modified skill")
        updated = File.read(skill_file)
        expect(updated).to include("Original skill content")
        expect(updated).to include("Additional instructions")
      end
    end

    context "with new_description" do
      it "updates the description metadata" do
        tool.execute(
          skill_name: "test-skill",
          new_description: "Updated description"
        )

        updated = File.read(skill_file)
        expect(updated).to include("description: Updated description")
        expect(updated).not_to include("Original description")
      end
    end

    context "with add_triggers" do
      it "adds new triggers to existing list" do
        tool.execute(
          skill_name: "test-skill",
          add_triggers: %w[keyword3 keyword4]
        )

        updated = File.read(skill_file)
        expect(updated).to include("keyword1")
        expect(updated).to include("keyword2")
        expect(updated).to include("keyword3")
        expect(updated).to include("keyword4")
      end

      it "avoids duplicate triggers" do
        tool.execute(
          skill_name: "test-skill",
          add_triggers: %w[keyword1 keyword3]
        )

        updated = File.read(skill_file)
        # keyword1 should appear once in triggers
        triggers_section = updated.match(/triggers:(.*?)(?=\n\w+:|---)/m)[0]
        expect(triggers_section.scan("keyword1").count).to eq(1)
        expect(triggers_section).to include("keyword3")
      end
    end

    context "with remove_triggers" do
      it "removes specified triggers" do
        tool.execute(
          skill_name: "test-skill",
          remove_triggers: ["keyword1"]
        )

        updated = File.read(skill_file)
        expect(updated).not_to include("keyword1")
        expect(updated).to include("keyword2")
      end

      it "removes triggers field when empty" do
        tool.execute(
          skill_name: "test-skill",
          remove_triggers: %w[keyword1 keyword2]
        )

        updated = File.read(skill_file)
        expect(updated).not_to include("triggers:")
      end
    end

    context "with set_always" do
      it "sets always flag to true" do
        tool.execute(
          skill_name: "test-skill",
          set_always: true
        )

        updated = File.read(skill_file)
        expect(updated).to include("always: true")
      end

      it "sets always flag to false" do
        tool.execute(
          skill_name: "test-skill",
          set_always: false
        )

        updated = File.read(skill_file)
        expect(updated).to include("always: false")
      end
    end

    context "with multiple modifications" do
      it "applies all changes together" do
        tool.execute(
          skill_name: "test-skill",
          new_description: "Completely updated",
          append_content: "New section",
          add_triggers: ["new-trigger"],
          set_always: true
        )

        updated = File.read(skill_file)
        expect(updated).to include("description: Completely updated")
        expect(updated).to include("New section")
        expect(updated).to include("new-trigger")
        expect(updated).to include("always: true")
      end
    end

    context "with skill without frontmatter" do
      before do
        File.write(skill_file, "Plain content without frontmatter")
      end

      it "adds frontmatter when modifying" do
        tool.execute(
          skill_name: "test-skill",
          new_description: "Added description"
        )

        updated = File.read(skill_file)
        expect(updated).to include("---")
        expect(updated).to include("description: Added description")
        expect(updated).to include("Plain content without frontmatter")
      end
    end
  end
end
