# frozen_string_literal: true

RSpec.describe Pocketrb::Agent::Context do
  let(:workspace) { Pathname.new(Dir.mktmpdir) }
  let(:context) { described_class.new(workspace: workspace) }

  after do
    FileUtils.rm_rf(workspace)
  end

  describe "#initialize" do
    it "loads default system prompt when no custom prompt provided" do
      expect(context.system_prompt).to include("Pocketrb")
      expect(context.system_prompt).to include("Tool Usage Guidelines")
    end

    it "uses custom system prompt when provided" do
      custom = described_class.new(system_prompt: "Custom instructions")
      expect(custom.system_prompt).to eq("Custom instructions")
    end

    it "loads IDENTITY.md from workspace if exists" do
      File.write(workspace.join("IDENTITY.md"), "Custom identity")
      ctx = described_class.new(workspace: workspace)

      expect(ctx.system_prompt).to include("Custom identity")
    end

    it "loads MEMORY.md from workspace if exists" do
      File.write(workspace.join("MEMORY.md"), "Background knowledge here")
      ctx = described_class.new(workspace: workspace)

      expect(ctx.system_prompt).to include("Background Knowledge")
      expect(ctx.system_prompt).to include("Background knowledge here")
    end

    it "handles missing workspace files gracefully" do
      # No files exist
      expect { described_class.new(workspace: workspace) }.not_to raise_error
    end

    it "stores skills summary when provided" do
      ctx = described_class.new(skills_summary: "Skill list")
      expect(ctx.skills_summary).to eq("Skill list")
    end
  end

  describe "#build_messages" do
    let(:history) do
      [
        Pocketrb::Providers::Message.user("Previous message"),
        Pocketrb::Providers::Message.assistant("Previous response")
      ]
    end

    it "builds message array with system message first" do
      messages = context.build_messages(history: history, current: "Hello")

      expect(messages.first.role).to eq("system")
      expect(messages.size).to eq(4) # system + 2 history + current
    end

    it "includes workspace in system message" do
      messages = context.build_messages(history: [], current: "Test")

      system_msg = messages.first
      expect(system_msg.content).to include("Working directory:")
      expect(system_msg.content).to include(workspace.to_s)
    end

    it "includes skills summary in system message" do
      ctx = described_class.new(workspace: workspace, skills_summary: "Available: git, search")
      messages = ctx.build_messages(history: [], current: "Test")

      expect(messages.first.content).to include("Available skills:")
      expect(messages.first.content).to include("git, search")
    end

    it "includes memory context when provided" do
      messages = context.build_messages(
        history: [],
        current: "Test",
        memory_context: "User prefers Ruby"
      )

      expect(messages.first.content).to include("Relevant context from memory:")
      expect(messages.first.content).to include("User prefers Ruby")
    end

    it "includes timestamp in system message" do
      messages = context.build_messages(history: [], current: "Test")

      expect(messages.first.content).to match(/Current time: \d{4}-\d{2}-\d{2}/)
    end

    it "appends current message to history" do
      messages = context.build_messages(history: history, current: "New message")

      expect(messages.last.content).to eq("New message")
      expect(messages.last.role).to eq("user")
    end

    it "strips media from history messages" do
      media_msg = Pocketrb::Providers::Message.new(
        role: "user",
        content: [
          { type: "text", text: "Look at this" },
          { type: "media", media: { filename: "image.png" } }
        ]
      )

      messages = context.build_messages(history: [media_msg], current: "Now?")

      # History message should have media stripped
      history_content = messages[1].content
      expect(history_content).to include("Look at this")
      expect(history_content).to include("[Previous image:")
    end
  end

  describe "#build_continuation" do
    let(:history) do
      [
        Pocketrb::Providers::Message.user("Question"),
        Pocketrb::Providers::Message.assistant("Let me check", tool_calls: ["call_1"]),
        Pocketrb::Providers::Message.tool_result(tool_call_id: "call_1", name: "exec", content: "Result")
      ]
    end

    it "builds continuation with system message and full history" do
      messages = context.build_continuation(history: history)

      expect(messages.first.role).to eq("system")
      expect(messages.size).to eq(4) # system + 3 history
    end

    it "includes memory context in system message" do
      messages = context.build_continuation(
        history: history,
        memory_context: "User likes concise answers"
      )

      expect(messages.first.content).to include("User likes concise answers")
    end
  end

  describe "#update_system_prompt" do
    it "replaces the system prompt" do
      context.update_system_prompt("New prompt")

      expect(context.system_prompt).to eq("New prompt")
    end
  end

  describe "#append_to_system_prompt" do
    it "adds content to existing prompt" do
      original = context.system_prompt
      context.append_to_system_prompt("Additional instructions")

      expect(context.system_prompt).to include(original)
      expect(context.system_prompt).to include("Additional instructions")
    end
  end

  describe "#update_skills_summary" do
    it "updates the skills summary" do
      context.update_skills_summary("New skills list")

      expect(context.skills_summary).to eq("New skills list")
    end
  end

  describe "media stripping" do
    it "converts media blocks to text placeholders in history" do
      media = Pocketrb::Bus::Media.new(
        type: :image,
        path: "/tmp/test.jpg",
        mime_type: "image/jpeg",
        filename: "test.jpg"
      )

      msg = Pocketrb::Providers::Message.user("Check this", media: [media])
      messages = context.build_messages(history: [msg], current: "What now?")

      # History message should have placeholder
      expect(messages[1].content).to include("[Previous image: test.jpg]")
    end

    it "preserves text-only messages unchanged" do
      msg = Pocketrb::Providers::Message.user("Text only")
      messages = context.build_messages(history: [msg], current: "Follow-up")

      expect(messages[1].content).to eq("Text only")
      expect(messages[1].role).to eq("user")
    end
  end
end
