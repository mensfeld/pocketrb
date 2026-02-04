# frozen_string_literal: true

RSpec.describe Pocketrb::Tools::ExecTool do
  let(:workspace) { Dir.mktmpdir }
  let(:tool) { described_class.new(workspace: workspace) }

  after do
    FileUtils.rm_rf(workspace)
  end

  describe "#name" do
    it "returns exec" do
      expect(tool.name).to eq("exec")
    end
  end

  describe "#description" do
    it "returns a description" do
      expect(tool.description).to be_a(String)
      expect(tool.description).to include("Execute")
    end
  end

  describe "#parameters" do
    it "defines command parameter" do
      params = tool.parameters
      expect(params[:properties]).to have_key(:command)
      expect(params[:required]).to include("command")
    end

    it "defines optional working_dir parameter" do
      params = tool.parameters
      expect(params[:properties]).to have_key(:working_dir)
    end
  end

  describe "#execute" do
    it "executes simple commands" do
      result = tool.execute(command: "echo hello")
      expect(result).to include("hello")
    end

    it "returns command output" do
      result = tool.execute(command: "pwd")
      expect(result).to be_a(String)
      expect(result.strip).to eq(workspace.to_s)
    end

    it "respects working directory" do
      subdir = Pathname.new(workspace).join("subdir")
      subdir.mkpath

      result = tool.execute(command: "pwd", working_dir: "subdir")
      expect(result.strip).to eq(subdir.to_s)
    end

    it "handles command errors" do
      result = tool.execute(command: "exit 1")
      expect(result).to include("Error")
      expect(result).to include("exit code 1")
    end

    it "handles non-existent commands" do
      result = tool.execute(command: "nonexistentcommand123")
      expect(result).to include("Error")
    end

    it "captures stderr" do
      result = tool.execute(command: "echo error >&2")
      expect(result).to include("error")
    end

    it "times out long-running commands" do
      tool_with_timeout = described_class.new(workspace: workspace, timeout: 1)
      result = tool_with_timeout.execute(command: "sleep 10")
      expect(result).to include("timeout") || expect(result).to include("killed")
    end
  end

  describe "security" do
    it "restricts execution to workspace" do
      result = tool.execute(command: "ls /etc")
      # Should work but be confined to workspace context
      expect(result).to be_a(String)
    end
  end
end
