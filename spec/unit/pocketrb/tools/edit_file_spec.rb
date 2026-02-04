# frozen_string_literal: true

RSpec.describe Pocketrb::Tools::EditFile do
  let(:workspace) { Pathname.new(Dir.mktmpdir) }
  let(:tool) { described_class.new(workspace: workspace) }
  let(:test_file) { workspace.join("test.rb") }

  before do
    File.write(test_file, <<~RUBY)
      def hello
        puts "Hello, world!"
      end

      def goodbye
        puts "Goodbye!"
      end
    RUBY
  end

  after do
    FileUtils.rm_rf(workspace)
  end

  describe "#name" do
    it "returns edit_file" do
      expect(tool.name).to eq("edit_file")
    end
  end

  describe "#execute" do
    context "with valid replacement" do
      it "replaces matching text" do
        result = tool.execute(
          path: "test.rb",
          old_string: 'puts "Hello, world!"',
          new_string: 'puts "Hi there!"'
        )

        expect(result).to include("Replaced 1 occurrence")
        expect(File.read(test_file)).to include('puts "Hi there!"')
        expect(File.read(test_file)).not_to include('puts "Hello, world!"')
      end

      it "preserves indentation and whitespace" do
        result = tool.execute(
          path: "test.rb",
          old_string: "  puts \"Hello, world!\"\n",
          new_string: "  puts \"Modified!\"\n"
        )

        expect(result).to include("Replaced 1 occurrence")
        content = File.read(test_file)
        expect(content).to include("  puts \"Modified!\"")
      end
    end

    context "with replace_all: true" do
      before do
        File.write(test_file, <<~RUBY)
          puts "test"
          puts "test"
          puts "test"
        RUBY
      end

      it "replaces all occurrences" do
        result = tool.execute(
          path: "test.rb",
          old_string: 'puts "test"',
          new_string: 'puts "updated"',
          replace_all: true
        )

        expect(result).to include("Replaced 3 occurrence(s)")
        content = File.read(test_file)
        expect(content.scan('puts "updated"').count).to eq(3)
        expect(content).not_to include('puts "test"')
      end
    end

    context "with non-unique old_string" do
      before do
        File.write(test_file, "line\nline\nline\n")
      end

      it "returns error when not using replace_all" do
        result = tool.execute(
          path: "test.rb",
          old_string: "line",
          new_string: "updated"
        )

        expect(result).to include("Error:")
        expect(result).to include("not unique")
        expect(result).to include("found 3 occurrences")
      end

      it "suggests using replace_all" do
        result = tool.execute(
          path: "test.rb",
          old_string: "line",
          new_string: "updated"
        )

        expect(result).to include("replace_all: true")
      end
    end

    context "with old_string not found" do
      it "returns error message" do
        result = tool.execute(
          path: "test.rb",
          old_string: "nonexistent text",
          new_string: "replacement"
        )

        expect(result).to include("Error:")
        expect(result).to include("not found")
      end

      it "suggests similar content when available" do
        result = tool.execute(
          path: "test.rb",
          old_string: "puts \"Hello\"", # Missing ", world!" part
          new_string: "replacement"
        )

        expect(result).to include("Similar content found")
        expect(result).to include("Line")
      end

      it "provides helpful error message" do
        result = tool.execute(
          path: "test.rb",
          old_string: "puts Hello", # Typo in the text
          new_string: "replacement"
        )

        expect(result).to include("not found")
        expect(result).to include("Similar content found")
          .or include("matches exactly")
      end
    end

    context "with missing file" do
      it "raises ToolError" do
        expect do
          tool.execute(
            path: "nonexistent.rb",
            old_string: "old",
            new_string: "new"
          )
        end.to raise_error(Pocketrb::ToolError, /does not exist/)
      end
    end

    context "with path outside workspace" do
      it "returns error" do
        expect do
          tool.execute(
            path: "/etc/passwd",
            old_string: "root",
            new_string: "hacked"
          )
        end.to raise_error(Pocketrb::ToolError)
      end
    end

    context "with multiline replacement" do
      it "handles multiline old_string" do
        result = tool.execute(
          path: "test.rb",
          old_string: "def hello\n  puts \"Hello, world!\"\nend",
          new_string: "def hello\n  puts \"Modified!\"\nend"
        )

        expect(result).to include("Replaced 1 occurrence")
        content = File.read(test_file)
        expect(content).to include("Modified!")
        expect(content).not_to include("Hello, world!")
      end
    end

    context "with empty strings" do
      it "handles empty new_string (deletion)" do
        result = tool.execute(
          path: "test.rb",
          old_string: 'puts "Hello, world!"',
          new_string: ""
        )

        expect(result).to include("Replaced 1 occurrence")
        expect(File.read(test_file)).not_to include('puts "Hello, world!"')
      end
    end
  end
end
