# frozen_string_literal: true

RSpec.describe Pocketrb::CLI::Skills do
  let(:workspace) { Pathname.new(Dir.mktmpdir) }
  let(:cli) { described_class.new([], { workspace: workspace }) }
  let(:loader) { instance_double(Pocketrb::Skills::Loader) }

  before do
    allow(Pocketrb::Skills::Loader).to receive(:new).and_return(loader)
  end

  after do
    FileUtils.rm_rf(workspace)
  end

  describe "#call" do
    context "with no skills" do
      before do
        allow(loader).to receive(:list_skills).and_return([])
      end

      it "shows message when no skills exist" do
        output = capture_stdout { cli.call }

        expect(output).to include("No skills found")
      end
    end

    context "with skills" do
      let(:skills) do
        [
          instance_double(
            Pocketrb::Skills::Skill,
            name: "basic-skill",
            description: "A basic test skill",
            always?: false,
            triggers: []
          ),
          instance_double(
            Pocketrb::Skills::Skill,
            name: "trigger-skill",
            description: "Skill with triggers",
            always?: false,
            triggers: %w[keyword1 keyword2]
          ),
          instance_double(
            Pocketrb::Skills::Skill,
            name: "always-skill",
            description: "Always active skill",
            always?: true,
            triggers: []
          )
        ]
      end

      before do
        allow(loader).to receive(:list_skills).and_return(skills)
      end

      it "lists all skills" do
        output = capture_stdout { cli.call }

        expect(output).to include("Available skills:")
        expect(output).to include("basic-skill")
        expect(output).to include("trigger-skill")
        expect(output).to include("always-skill")
      end

      it "shows skill descriptions" do
        output = capture_stdout { cli.call }

        expect(output).to include("A basic test skill")
        expect(output).to include("Skill with triggers")
        expect(output).to include("Always active skill")
      end

      it "shows triggers for skills that have them" do
        output = capture_stdout { cli.call }

        expect(output).to include("triggers: keyword1, keyword2")
      end

      it "shows always flag for always-on skills" do
        output = capture_stdout { cli.call }

        expect(output).to include("always")
      end

      it "does not show flags for basic skills" do
        output = capture_stdout { cli.call }

        # basic-skill line should not have parentheses (no flags)
        basic_line = output.lines.find { |l| l.include?("basic-skill") }
        expect(basic_line).not_to be_nil
        expect(basic_line).not_to include("(")
      end
    end
  end

  private

  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end
end
