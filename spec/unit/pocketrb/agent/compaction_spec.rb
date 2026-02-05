# frozen_string_literal: true

RSpec.describe Pocketrb::Agent::Compaction do
  let(:provider) { instance_double(Pocketrb::Providers::Base) }
  let(:compaction) { described_class.new(provider: provider) }

  before do
    allow(provider).to receive(:default_model).and_return("test-model")
  end

  describe "#initialize" do
    it "stores provider" do
      expect(compaction.provider).to eq(provider)
    end

    it "uses provider default model" do
      expect(compaction.model).to eq("test-model")
    end

    it "accepts custom model" do
      custom = described_class.new(provider: provider, model: "custom-model")
      expect(custom.model).to eq("custom-model")
    end

    it "uses default message threshold" do
      expect(compaction.message_threshold).to eq(described_class::DEFAULT_MESSAGE_THRESHOLD)
    end

    it "accepts custom message threshold" do
      custom = described_class.new(provider: provider, message_threshold: 100)
      expect(custom.message_threshold).to eq(100)
    end

    it "uses default token threshold" do
      expect(compaction.token_threshold).to eq(described_class::DEFAULT_TOKEN_THRESHOLD)
    end

    it "accepts custom token threshold" do
      custom = described_class.new(provider: provider, token_threshold: 10_000)
      expect(custom.token_threshold).to eq(10_000)
    end

    it "uses default keep_recent" do
      expect(compaction.keep_recent).to eq(described_class::DEFAULT_KEEP_RECENT)
    end

    it "accepts custom keep_recent" do
      custom = described_class.new(provider: provider, keep_recent: 5)
      expect(custom.keep_recent).to eq(5)
    end
  end

  describe "#needs_compaction?" do
    it "returns false for empty messages" do
      expect(compaction.needs_compaction?([])).to be false
    end

    it "returns false when messages below keep_recent" do
      messages = Array.new(10) { Pocketrb::Providers::Message.user("Test") }
      expect(compaction.needs_compaction?(messages)).to be false
    end

    it "returns true when messages exceed threshold" do
      messages = Array.new(50) { Pocketrb::Providers::Message.user("Test") }
      expect(compaction.needs_compaction?(messages)).to be true
    end

    it "returns true when estimated tokens exceed threshold" do
      # Create messages with lots of content to exceed 50K token threshold
      # 11000 chars * 20 = 220K chars = ~55K tokens
      large_content = "x" * 11_000
      messages = Array.new(20) { Pocketrb::Providers::Message.user(large_content) }

      expect(compaction.needs_compaction?(messages)).to be true
    end

    it "returns false when both thresholds not exceeded" do
      messages = Array.new(20) { Pocketrb::Providers::Message.user("Short") }
      expect(compaction.needs_compaction?(messages)).to be false
    end
  end

  describe "#estimate_tokens" do
    it "estimates tokens for string content" do
      messages = [Pocketrb::Providers::Message.user("Hello world")]
      tokens = compaction.estimate_tokens(messages)

      # "Hello world" = 11 chars, ~2-3 tokens
      expect(tokens).to be >= 2
      expect(tokens).to be <= 3
    end

    it "estimates tokens for array content with text blocks" do
      content = [
        { type: "text", text: "Hello" },
        { type: "text", text: "World" }
      ]
      message = Pocketrb::Providers::Message.new(role: "user", content: content)
      tokens = compaction.estimate_tokens([message])

      # "HelloWorld" = 10 chars, ~2 tokens
      expect(tokens).to be >= 2
      expect(tokens).to be <= 3
    end

    it "estimates tokens for non-text blocks" do
      content = [
        { type: "image", source: "data:..." }
      ]
      message = Pocketrb::Providers::Message.new(role: "user", content: content)
      tokens = compaction.estimate_tokens([message])

      # Uses 50 as estimate for non-text
      expect(tokens).to be >= 12
    end

    it "handles multiple messages" do
      messages = [
        Pocketrb::Providers::Message.user("First"),
        Pocketrb::Providers::Message.assistant("Second"),
        Pocketrb::Providers::Message.user("Third")
      ]
      tokens = compaction.estimate_tokens(messages)

      expect(tokens).to be > 0
    end
  end

  describe "#compact" do
    let(:messages) do
      Array.new(50) do |i|
        Pocketrb::Providers::Message.user("Message #{i}")
      end
    end

    before do
      response = instance_double(
        Pocketrb::Providers::LLMResponse,
        content: "Summary of conversation"
      )
      allow(provider).to receive(:chat).and_return(response)
      allow(Pocketrb.logger).to receive(:info)
    end

    it "returns messages unchanged if no compaction needed" do
      small = Array.new(10) { Pocketrb::Providers::Message.user("Test") }
      result = compaction.compact(small)

      expect(result).to eq(small)
    end

    it "compacts when threshold exceeded" do
      result = compaction.compact(messages)

      # Should have summary + recent messages
      expect(result.length).to be < messages.length
      expect(result.first.content).to include("Previous conversation summary")
    end

    it "keeps recent messages uncompacted" do
      result = compaction.compact(messages)

      # Last 15 messages (DEFAULT_KEEP_RECENT) should be preserved
      expect(result.last(15)).to eq(messages.last(15))
    end

    it "logs compaction" do
      compaction.compact(messages)

      expect(Pocketrb.logger).to have_received(:info).with(/Compacting/)
    end

    it "calls provider to generate summary" do
      compaction.compact(messages)

      expect(provider).to have_received(:chat)
    end

    it "handles provider errors with fallback summary" do
      allow(provider).to receive(:chat).and_raise(StandardError, "API error")
      allow(Pocketrb.logger).to receive(:error)

      result = compaction.compact(messages)

      expect(result.first.content).to include("Previous conversation")
    end
  end

  describe "#compact_session!" do
    let(:session) { Pocketrb::Session::Session.new(key: "test") }

    before do
      response = instance_double(
        Pocketrb::Providers::LLMResponse,
        content: "Summary"
      )
      allow(provider).to receive(:chat).and_return(response)
      allow(Pocketrb.logger).to receive(:info)
    end

    it "returns false when no compaction needed" do
      10.times { session.add_message(role: "user", content: "Test") }

      result = compaction.compact_session!(session)

      expect(result).to be false
    end

    it "compacts session when threshold exceeded" do
      50.times do |i|
        session.add_message(role: "user", content: "Message #{i}")
      end

      result = compaction.compact_session!(session)

      expect(result).to be true
      expect(session.message_count).to be < 50
    end

    it "filters out system messages before compaction" do
      session.add_message(role: "system", content: "System prompt")
      50.times { session.add_message(role: "user", content: "Test") }

      compaction.compact_session!(session)

      # System message should be excluded from compaction count
      expect(session.messages.any? { |m| m.role == "system" }).to be false
    end

    it "updates session messages in place" do
      50.times { session.add_message(role: "user", content: "Test") }
      original_count = session.message_count

      compaction.compact_session!(session)

      expect(session.message_count).to be < original_count
    end

    it "logs session compaction" do
      50.times { session.add_message(role: "user", content: "Test") }

      compaction.compact_session!(session)

      expect(Pocketrb.logger).to have_received(:info).with(/Session compacted/)
    end
  end

  describe "private methods" do
    describe "#extract_text_content" do
      it "extracts string content directly" do
        result = compaction.send(:extract_text_content, "Hello")
        expect(result).to eq("Hello")
      end

      it "extracts text from array of text blocks" do
        content = [
          { type: "text", text: "Hello" },
          { type: "text", text: "World" }
        ]
        result = compaction.send(:extract_text_content, content)
        expect(result).to eq("Hello\nWorld")
      end

      it "extracts string blocks from array" do
        content = %w[Hello World]
        result = compaction.send(:extract_text_content, content)
        expect(result).to eq("Hello\nWorld")
      end

      it "ignores non-text blocks" do
        content = [
          { type: "text", text: "Hello" },
          { type: "image", source: "..." }
        ]
        result = compaction.send(:extract_text_content, content)
        expect(result).to eq("Hello")
      end
    end

    describe "#build_summary_message" do
      it "wraps summary in markers" do
        message = compaction.send(:build_summary_message, "Test summary")

        expect(message.role).to eq("user")
        expect(message.content).to include("[Previous conversation summary]")
        expect(message.content).to include("Test summary")
        expect(message.content).to include("[End of summary")
      end
    end

    describe "#basic_summary" do
      it "creates fallback summary with message counts" do
        messages = [
          Pocketrb::Providers::Message.user("Q1"),
          Pocketrb::Providers::Message.assistant("A1"),
          Pocketrb::Providers::Message.user("Q2")
        ]

        summary = compaction.send(:basic_summary, messages)

        expect(summary).to include("2 user messages")
        expect(summary).to include("1 assistant")
      end

      it "includes tool call count when present" do
        messages = [
          Pocketrb::Providers::Message.user("Q"),
          Pocketrb::Providers::Message.new(role: "tool", content: "Result", tool_call_id: "1")
        ]

        summary = compaction.send(:basic_summary, messages)

        expect(summary).to include("1 tool call")
      end

      it "includes recent user queries" do
        messages = [
          Pocketrb::Providers::Message.user("Query 1"),
          Pocketrb::Providers::Message.assistant("Response"),
          Pocketrb::Providers::Message.user("Query 2")
        ]

        summary = compaction.send(:basic_summary, messages)

        expect(summary).to include("Recent topics")
      end
    end

    describe "#format_for_summary" do
      it "formats messages with role and content" do
        messages = [
          Pocketrb::Providers::Message.user("Hello"),
          Pocketrb::Providers::Message.assistant("Hi there")
        ]

        formatted = compaction.send(:format_for_summary, messages)

        expect(formatted).to include("User: Hello")
        expect(formatted).to include("Assistant: Hi there")
      end

      it "truncates long content" do
        long_content = "x" * 1000
        messages = [Pocketrb::Providers::Message.user(long_content)]

        formatted = compaction.send(:format_for_summary, messages)

        expect(formatted).to include("...")
        expect(formatted.length).to be < long_content.length
      end
    end
  end
end
