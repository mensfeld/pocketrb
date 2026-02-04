# frozen_string_literal: true

RSpec.describe Pocketrb::Tools::Exec do
  let(:workspace) { Pathname.new(Dir.mktmpdir) }
  let(:tool) { described_class.new(workspace: workspace) }

  after do
    FileUtils.rm_rf(workspace)
  end

  describe "#name" do
    it "returns exec" do
      expect(tool.name).to eq("exec")
    end
  end

  describe "#execute" do
    context "with simple command" do
      it "executes successfully" do
        result = tool.execute(command: "echo 'hello'")

        expect(result).to include("Exit code: 0")
        expect(result).to include("hello")
      end

      it "captures stdout" do
        result = tool.execute(command: "pwd")

        expect(result).to include("STDOUT:")
        expect(result).to include(workspace.to_s)
      end
    end

    context "with failed command" do
      it "returns non-zero exit code" do
        result = tool.execute(command: "ls /nonexistent")

        expect(result).to match(/Exit code: [^0]/)
      end

      it "captures stderr" do
        result = tool.execute(command: "ls /nonexistent 2>&1")

        expect(result).to include("No such file")
          .or include("cannot access")
          .or include("not found")
      end
    end

    context "with working directory" do
      it "uses specified directory" do
        subdir = workspace.join("subdir")
        FileUtils.mkdir_p(subdir)

        result = tool.execute(command: "pwd", working_dir: "subdir")

        expect(result).to include("subdir")
      end

      it "rejects path outside workspace" do
        result = tool.execute(command: "pwd", working_dir: "/etc")

        expect(result).to include("Error:")
        expect(result).to include("outside workspace")
      end
    end

    context "with timeout" do
      it "kills command that exceeds timeout" do
        # Force foreground execution with background: false to test timeout
        result = tool.execute(command: "ruby -e 'sleep 10'", timeout: 1, background: false)

        expect(result).to include("timed out")
      end
    end

    context "with dangerous commands" do
      it "blocks rm -rf /" do
        result = tool.execute(command: "rm -rf /")

        expect(result).to include("Error:")
        expect(result).to include("blocked for security")
      end

      it "blocks system shutdown" do
        result = tool.execute(command: "shutdown now")

        expect(result).to include("Error:")
        expect(result).to include("blocked for security")
      end
    end

    context "output truncation" do
      it "truncates very long output" do
        # Generate output larger than MAX_OUTPUT_SIZE
        long_command = "ruby -e 'puts \"x\" * 150_000'"
        result = tool.execute(command: long_command)

        expect(result).to include("truncated")
      end
    end

    context "empty output" do
      it "indicates no output" do
        result = tool.execute(command: "true")

        expect(result).to include("(no output)")
      end
    end
  end

  describe "timeout selection" do
    it "uses simple timeout for quick commands" do
      expect(tool.send(:smart_timeout, "ls")).to eq(30)
      expect(tool.send(:smart_timeout, "pwd")).to eq(30)
    end

    it "uses standard timeout for normal commands" do
      expect(tool.send(:smart_timeout, "grep something file.txt")).to eq(120)
    end
  end

  describe "dangerous command detection" do
    it "detects rm -rf /" do
      expect(tool.send(:dangerous_command?, "rm -rf /")).to be true
    end

    it "allows safe rm commands" do
      expect(tool.send(:dangerous_command?, "rm -rf ./temp")).to be false
    end
  end
end
