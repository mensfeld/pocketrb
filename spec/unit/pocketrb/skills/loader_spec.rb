# frozen_string_literal: true

RSpec.describe Pocketrb::Skills::Loader do
  let(:workspace) { Pathname.new(Dir.mktmpdir) }
  let(:builtin_dir) { Pathname.new(Dir.mktmpdir) }
  let(:loader) { described_class.new(workspace: workspace, builtin_dir: builtin_dir) }

  after do
    FileUtils.rm_rf(workspace)
    FileUtils.rm_rf(builtin_dir)
  end

  describe "#initialize" do
    it "sets workspace" do
      expect(loader.workspace).to eq(workspace)
    end

    it "sets custom builtin_dir" do
      expect(loader.builtin_dir).to eq(builtin_dir)
    end

    it "defaults builtin_dir to gem's builtin directory" do
      l = described_class.new(workspace: workspace)

      expect(l.builtin_dir.to_s).to include("lib/pocketrb/skills/builtin")
    end
  end

  describe "#list_skills" do
    context "with no skills" do
      it "returns empty array" do
        expect(loader.list_skills).to eq([])
      end
    end

    context "with workspace skills" do
      before do
        skills_dir = workspace.join("skills")
        FileUtils.mkdir_p(skills_dir.join("skill1"))
        FileUtils.mkdir_p(skills_dir.join("skill2"))

        File.write(skills_dir.join("skill1/SKILL.md"), <<~MD)
          ---
          name: skill1
          description: First skill
          ---

          Content for skill1
        MD

        File.write(skills_dir.join("skill2/SKILL.md"), <<~MD)
          ---
          name: skill2
          description: Second skill
          ---

          Content for skill2
        MD
      end

      it "loads all skills" do
        skills = loader.list_skills

        expect(skills.length).to eq(2)
        expect(skills.map(&:name)).to contain_exactly("skill1", "skill2")
      end
    end

    context "with builtin skills" do
      before do
        FileUtils.mkdir_p(builtin_dir.join("builtin1"))

        File.write(builtin_dir.join("builtin1/SKILL.md"), <<~MD)
          ---
          name: builtin1
          description: Builtin skill
          ---

          Builtin content
        MD
      end

      it "loads builtin skills" do
        skills = loader.list_skills

        expect(skills.length).to eq(1)
        expect(skills.first.name).to eq("builtin1")
      end
    end

    context "with both workspace and builtin skills" do
      before do
        workspace_skills = workspace.join("skills")
        FileUtils.mkdir_p(workspace_skills.join("custom"))

        File.write(workspace_skills.join("custom/SKILL.md"), <<~MD)
          ---
          name: custom
          description: Custom skill
          ---

          Custom content
        MD

        FileUtils.mkdir_p(builtin_dir.join("builtin"))

        File.write(builtin_dir.join("builtin/SKILL.md"), <<~MD)
          ---
          name: builtin
          description: Builtin skill
          ---

          Builtin content
        MD
      end

      it "loads skills from both directories" do
        skills = loader.list_skills

        expect(skills.length).to eq(2)
        expect(skills.map(&:name)).to contain_exactly("custom", "builtin")
      end
    end

    context "with filter_unavailable" do
      before do
        skills_dir = workspace.join("skills")
        FileUtils.mkdir_p(skills_dir.join("available"))
        FileUtils.mkdir_p(skills_dir.join("unavailable"))

        File.write(skills_dir.join("available/SKILL.md"), <<~MD)
          ---
          name: available
          description: Available skill
          ---

          Content
        MD

        File.write(skills_dir.join("unavailable/SKILL.md"), <<~MD)
          ---
          name: unavailable
          description: Unavailable skill
          requires: env:MISSING_ENV_VAR
          ---

          Content
        MD
      end

      it "filters unavailable skills by default" do
        skills = loader.list_skills

        expect(skills.length).to eq(1)
        expect(skills.first.name).to eq("available")
      end

      it "includes unavailable skills when filter is false" do
        skills = loader.list_skills(filter_unavailable: false)

        expect(skills.length).to eq(2)
        expect(skills.map(&:name)).to contain_exactly("available", "unavailable")
      end
    end
  end

  describe "#load_skill" do
    before do
      skills_dir = workspace.join("skills")
      FileUtils.mkdir_p(skills_dir.join("test-skill"))

      File.write(skills_dir.join("test-skill/SKILL.md"), <<~MD)
        ---
        name: test-skill
        description: Test skill
        ---

        Test content
      MD
    end

    it "loads skill by name from workspace" do
      skill = loader.load_skill("test-skill")

      expect(skill).not_to be_nil
      expect(skill.name).to eq("test-skill")
      expect(skill.description).to eq("Test skill")
    end

    it "caches loaded skills" do
      skill1 = loader.load_skill("test-skill")
      skill2 = loader.load_skill("test-skill")

      expect(skill1).to be(skill2)
    end

    it "returns nil for nonexistent skill" do
      skill = loader.load_skill("nonexistent")

      expect(skill).to be_nil
    end

    it "prefers workspace skills over builtin" do
      workspace_skills = workspace.join("skills")
      FileUtils.mkdir_p(workspace_skills.join("override"))

      File.write(workspace_skills.join("override/SKILL.md"), <<~MD)
        ---
        name: override
        description: Workspace version
        ---

        Workspace content
      MD

      FileUtils.mkdir_p(builtin_dir.join("override"))

      File.write(builtin_dir.join("override/SKILL.md"), <<~MD)
        ---
        name: override
        description: Builtin version
        ---

        Builtin content
      MD

      skill = loader.load_skill("override")

      expect(skill.description).to eq("Workspace version")
    end
  end

  describe "#get_always_skills" do
    before do
      skills_dir = workspace.join("skills")
      FileUtils.mkdir_p(skills_dir.join("always-skill"))
      FileUtils.mkdir_p(skills_dir.join("normal-skill"))

      File.write(skills_dir.join("always-skill/SKILL.md"), <<~MD)
        ---
        name: always-skill
        description: Always active
        always: true
        ---

        Content
      MD

      File.write(skills_dir.join("normal-skill/SKILL.md"), <<~MD)
        ---
        name: normal-skill
        description: Normal skill
        ---

        Content
      MD
    end

    it "returns only skills with always flag" do
      skills = loader.get_always_skills

      expect(skills.length).to eq(1)
      expect(skills.first.name).to eq("always-skill")
    end
  end

  describe "#get_triggered_skills" do
    before do
      skills_dir = workspace.join("skills")
      FileUtils.mkdir_p(skills_dir.join("git-skill"))
      FileUtils.mkdir_p(skills_dir.join("test-skill"))

      File.write(skills_dir.join("git-skill/SKILL.md"), <<~MD)
        ---
        name: git-skill
        description: Git commands
        triggers:
        - git
        - github
        ---

        Content
      MD

      File.write(skills_dir.join("test-skill/SKILL.md"), <<~MD)
        ---
        name: test-skill
        description: Testing
        triggers:
        - test
        - spec
        ---

        Content
      MD
    end

    it "returns skills triggered by message" do
      skills = loader.get_triggered_skills("I need help with git")

      expect(skills.length).to eq(1)
      expect(skills.first.name).to eq("git-skill")
    end

    it "returns multiple matching skills" do
      skills = loader.get_triggered_skills("Run git tests")

      expect(skills.length).to eq(2)
      expect(skills.map(&:name)).to contain_exactly("git-skill", "test-skill")
    end

    it "returns empty array when no matches" do
      skills = loader.get_triggered_skills("Something else")

      expect(skills).to eq([])
    end
  end

  describe "#build_skills_summary" do
    context "with skills" do
      before do
        skills_dir = workspace.join("skills")
        FileUtils.mkdir_p(skills_dir.join("skill1"))

        File.write(skills_dir.join("skill1/SKILL.md"), <<~MD)
          ---
          name: skill1
          description: First skill
          ---

          Content
        MD
      end

      it "builds XML summary" do
        summary = loader.build_skills_summary

        expect(summary).to include("<available-skills>")
        expect(summary).to include("- skill1: First skill")
        expect(summary).to include("</available-skills>")
      end
    end

    context "with no skills" do
      it "returns empty string" do
        summary = loader.build_skills_summary

        expect(summary).to eq("")
      end
    end
  end

  describe "#build_skills_prompt" do
    before do
      skills_dir = workspace.join("skills")
      FileUtils.mkdir_p(skills_dir.join("skill1"))
      FileUtils.mkdir_p(skills_dir.join("skill2"))

      File.write(skills_dir.join("skill1/SKILL.md"), <<~MD)
        ---
        name: skill1
        description: First skill
        ---

        Skill 1 content
      MD

      File.write(skills_dir.join("skill2/SKILL.md"), <<~MD)
        ---
        name: skill2
        description: Second skill
        ---

        Skill 2 content
      MD
    end

    it "builds prompt from specific skills" do
      prompt = loader.build_skills_prompt(%w[skill1 skill2])

      expect(prompt).to include('<skill name="skill1">')
      expect(prompt).to include("Skill 1 content")
      expect(prompt).to include('<skill name="skill2">')
      expect(prompt).to include("Skill 2 content")
    end

    it "skips nonexistent skills" do
      prompt = loader.build_skills_prompt(%w[skill1 nonexistent])

      expect(prompt).to include('<skill name="skill1">')
      expect(prompt).not_to include("nonexistent")
    end
  end

  describe "#clear_cache!" do
    before do
      skills_dir = workspace.join("skills")
      FileUtils.mkdir_p(skills_dir.join("cached"))

      File.write(skills_dir.join("cached/SKILL.md"), <<~MD)
        ---
        name: cached
        description: Cached skill
        ---

        Content
      MD
    end

    it "clears the cache" do
      skill1 = loader.load_skill("cached")
      loader.clear_cache!
      skill2 = loader.load_skill("cached")

      expect(skill1).not_to be(skill2)
    end
  end

  describe "skill file parsing" do
    context "with frontmatter" do
      before do
        skills_dir = workspace.join("skills")
        FileUtils.mkdir_p(skills_dir.join("with-fm"))

        File.write(skills_dir.join("with-fm/SKILL.md"), <<~MD)
          ---
          name: with-fm
          description: Has frontmatter
          triggers:
          - keyword
          ---

          Body content
        MD
      end

      it "parses frontmatter and body" do
        skill = loader.load_skill("with-fm")

        expect(skill.name).to eq("with-fm")
        expect(skill.description).to eq("Has frontmatter")
        expect(skill.content).to eq("Body content")
        expect(skill.triggers).to eq(["keyword"])
      end
    end

    context "without frontmatter" do
      before do
        skills_dir = workspace.join("skills")
        FileUtils.mkdir_p(skills_dir.join("no-fm"))

        File.write(skills_dir.join("no-fm/SKILL.md"), <<~MD)
          # Heading

          Body content
        MD
      end

      it "uses directory name and extracts description from content" do
        skill = loader.load_skill("no-fm")

        expect(skill.name).to eq("no-fm")
        expect(skill.description).to eq("Heading")
        expect(skill.content).to include("# Heading")
      end
    end
  end
end
