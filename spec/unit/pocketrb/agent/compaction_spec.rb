# frozen_string_literal: true

RSpec.describe Pocketrb::Agent::Compaction do
  let(:provider) { instance_double(Pocketrb::Providers::Base) }
  let(:compaction) { described_class.new(provider: provider) }

  before do
    allow(provider).to receive_messages(default_model: "test-model", context_window: 200_000)
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

    it "uses provider context_window by default" do
      expect(compaction.context_window).to eq(200_000)
    end

    it "accepts custom context_window" do
      custom = described_class.new(provider: provider, context_window: 100_000)
      expect(custom.context_window).to eq(100_000)
    end

    it "uses default context_pressure" do
      expect(compaction.context_pressure).to eq(described_class::DEFAULT_CONTEXT_PRESSURE)
    end

    it "accepts custom context_pressure" do
      custom = described_class.new(provider: provider, context_pressure: 0.5)
      expect(custom.context_pressure).to eq(0.5)
    end

    it "stores on_compact callback" do
      callback = proc { |_summary, _count| }
      custom = described_class.new(provider: provider, on_compact: callback)
      expect(custom.on_compact).to eq(callback)
    end

    it "raises ArgumentError for invalid context_window" do
      expect { described_class.new(provider: provider, context_window: -1) }
        .to raise_error(ArgumentError, /context_window must be a positive number/)
    end

    it "raises ArgumentError for zero context_window" do
      expect { described_class.new(provider: provider, context_window: 0) }
        .to raise_error(ArgumentError, /context_window must be a positive number/)
    end

    it "raises ArgumentError for context_pressure above 1.0" do
      expect { described_class.new(provider: provider, context_pressure: 1.5) }
        .to raise_error(ArgumentError, /context_pressure must be between 0.0 and 1.0/)
    end

    it "raises ArgumentError for negative context_pressure" do
      expect { described_class.new(provider: provider, context_pressure: -0.1) }
        .to raise_error(ArgumentError, /context_pressure must be between 0.0 and 1.0/)
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

    context "with pressure-based threshold" do
      it "returns true when estimated tokens exceed context pressure" do
        # Use a small context_window so pressure triggers easily
        small_window = described_class.new(
          provider: provider,
          context_window: 1000,
          context_pressure: 0.5,
          # Set high fixed thresholds so only pressure triggers
          message_threshold: 1000,
          token_threshold: 1_000_000
        )

        # 20 messages * "x" * 200 chars = 4000 chars / 4 = 1000 tokens > 1000 * 0.5 = 500
        messages = Array.new(20) { Pocketrb::Providers::Message.user("x" * 200) }
        expect(small_window.needs_compaction?(messages)).to be true
      end

      it "returns false when below context pressure" do
        small_window = described_class.new(
          provider: provider,
          context_window: 100_000,
          context_pressure: 0.9,
          message_threshold: 1000,
          token_threshold: 1_000_000
        )

        messages = Array.new(20) { Pocketrb::Providers::Message.user("Short") }
        expect(small_window.needs_compaction?(messages)).to be false
      end
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

    context "with on_compact callback" do
      it "fires callback after successful compaction" do
        callback_args = nil
        callback = proc { |summary, count| callback_args = [summary, count] }
        compaction_with_cb = described_class.new(provider: provider, on_compact: callback)

        compaction_with_cb.compact(messages)

        expect(callback_args).not_to be_nil
        expect(callback_args[0]).to eq("Summary of conversation")
        expect(callback_args[1]).to eq(35) # 50 - 15 keep_recent
      end

      it "does not fire callback when no compaction needed" do
        called = false
        callback = proc { |_summary, _count| called = true }
        compaction_with_cb = described_class.new(provider: provider, on_compact: callback)

        small = Array.new(10) { Pocketrb::Providers::Message.user("Test") }
        compaction_with_cb.compact(small)

        expect(called).to be false
      end
    end

    context "with rolling summaries" do
      it "passes prior summary to generate_summary when first message is a summary" do
        summary_msg = Pocketrb::Providers::Message.user(
          "[Previous conversation summary]\nOld summary content\n[End of summary - continuing conversation]"
        )
        msgs = [summary_msg] + Array.new(49) { |i| Pocketrb::Providers::Message.user("Message #{i}") }

        compaction.compact(msgs)

        expect(provider).to have_received(:chat) do |args|
          user_msg = args[:messages].find { |m| m.role == "user" }
          expect(user_msg.content).to include("Prior summary from earlier conversation:")
          expect(user_msg.content).to include("Old summary content")
        end
      end

      it "does not include prior summary when first message is not a summary" do
        compaction.compact(messages)

        expect(provider).to have_received(:chat) do |args|
          user_msg = args[:messages].find { |m| m.role == "user" }
          expect(user_msg.content).not_to include("Prior summary from earlier conversation:")
        end
      end
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

    it "is thread-safe via mutex" do
      50.times { session.add_message(role: "user", content: "Test") }

      # Should not deadlock when called from multiple threads
      threads = Array.new(3) do
        Thread.new { compaction.compact_session!(session) }
      end

      expect { threads.each(&:join) }.not_to raise_error
    end
  end

  describe "#schedule_compaction" do
    let(:session) { Pocketrb::Session::Session.new(key: "test") }

    before do
      response = instance_double(
        Pocketrb::Providers::LLMResponse,
        content: "Summary"
      )
      allow(provider).to receive(:chat).and_return(response)
      allow(Pocketrb.logger).to receive(:info)
    end

    it "returns nil when compaction not needed" do
      10.times { session.add_message(role: "user", content: "Test") }

      result = compaction.schedule_compaction(session)

      expect(result).to be_nil
    end

    it "returns a thread when compaction is scheduled" do
      50.times { session.add_message(role: "user", content: "Test") }

      thread = compaction.schedule_compaction(session)

      expect(thread).to be_a(Thread)
      thread.join
    end

    it "compacts session in background" do
      50.times { session.add_message(role: "user", content: "Test") }

      thread = compaction.schedule_compaction(session)
      thread.join

      expect(session.message_count).to be < 50
    end

    it "returns nil if already compacting" do
      50.times { session.add_message(role: "user", content: "Test") }

      # Simulate slow compaction
      allow(provider).to receive(:chat) do
        sleep 0.1
        instance_double(Pocketrb::Providers::LLMResponse, content: "Summary")
      end

      first_thread = compaction.schedule_compaction(session)
      second_result = compaction.schedule_compaction(session)

      expect(second_result).to be_nil

      first_thread.join
    end

    it "sets compacting? to true during compaction" do
      50.times { session.add_message(role: "user", content: "Test") }

      allow(provider).to receive(:chat) do
        sleep 0.1
        instance_double(Pocketrb::Providers::LLMResponse, content: "Summary")
      end

      thread = compaction.schedule_compaction(session)
      expect(compaction.compacting?).to be true

      thread.join
      expect(compaction.compacting?).to be false
    end
  end

  describe "#wait_for_compaction" do
    let(:session) { Pocketrb::Session::Session.new(key: "test") }

    before do
      response = instance_double(
        Pocketrb::Providers::LLMResponse,
        content: "Summary"
      )
      allow(provider).to receive(:chat).and_return(response)
      allow(Pocketrb.logger).to receive(:info)
    end

    it "returns true when no compaction is running" do
      expect(compaction.wait_for_compaction).to be true
    end

    it "waits for background compaction to finish" do
      50.times { session.add_message(role: "user", content: "Test") }

      compaction.schedule_compaction(session)
      result = compaction.wait_for_compaction

      expect(result).to be true
      expect(compaction.compacting?).to be false
    end

    it "respects timeout" do
      50.times { session.add_message(role: "user", content: "Test") }

      allow(provider).to receive(:chat) do
        sleep 5
        instance_double(Pocketrb::Providers::LLMResponse, content: "Summary")
      end

      thread = compaction.schedule_compaction(session)
      result = compaction.wait_for_compaction(timeout: 0.01)

      expect(result).to be false

      # Clean up
      thread.kill
      thread.join
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

    describe "#extract_prior_summary" do
      it "returns nil for empty messages" do
        result = compaction.send(:extract_prior_summary, [])
        expect(result).to be_nil
      end

      it "returns nil when first message is not a summary" do
        messages = [Pocketrb::Providers::Message.user("Regular message")]
        result = compaction.send(:extract_prior_summary, messages)
        expect(result).to be_nil
      end

      it "extracts summary text from a summary message" do
        summary_msg = Pocketrb::Providers::Message.user(
          "[Previous conversation summary]\nThe user discussed topic X\n[End of summary - continuing conversation]"
        )
        messages = [summary_msg]
        result = compaction.send(:extract_prior_summary, messages)
        expect(result).to eq("The user discussed topic X")
      end

      it "returns nil when marker appears mid-content (not at start)" do
        msg = Pocketrb::Providers::Message.user(
          "Some text before [Previous conversation summary]\nFake summary\n[End of summary - continuing conversation]"
        )
        result = compaction.send(:extract_prior_summary, [msg])
        expect(result).to be_nil
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
