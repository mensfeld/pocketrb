# frozen_string_literal: true

RSpec.describe Pocketrb::Tools::Memory do
  let(:memory) { instance_double(Pocketrb::Memory) }
  let(:context) { { memory: memory } }
  let(:tool) { described_class.new(context) }

  describe "#name" do
    it "returns memory" do
      expect(tool.name).to eq("memory")
    end
  end

  describe "#description" do
    it "includes action descriptions" do
      desc = tool.description

      expect(desc).to include("store")
      expect(desc).to include("recall")
      expect(desc).to include("search")
      expect(desc).to include("recent")
      expect(desc).to include("stats")
    end
  end

  describe "#parameters" do
    it "requires action parameter" do
      expect(tool.parameters[:required]).to eq(["action"])
    end

    it "includes action enum" do
      action_prop = tool.parameters[:properties][:action]

      expect(action_prop[:enum]).to include("store", "recall", "search", "recent", "stats")
    end

    it "includes category enum" do
      category_prop = tool.parameters[:properties][:category]

      expect(category_prop[:enum]).to include("learned", "user", "preference", "context")
    end
  end

  describe "#available?" do
    it "returns true when memory is in context" do
      expect(tool.available?).to be true
    end

    it "returns false when memory is nil" do
      tool_without_memory = described_class.new({})

      expect(tool_without_memory.available?).to be false
    end
  end

  describe "#execute" do
    context "without memory instance" do
      let(:tool_without_memory) { described_class.new({}) }

      it "returns error" do
        result = tool_without_memory.execute(action: "store")

        expect(result).to include("Error:")
        expect(result).to include("Memory not initialized")
      end
    end

    context "with store action" do
      before do
        allow(memory).to receive(:remember_learned).and_return("Stored: test")
        allow(memory).to receive(:remember_user).and_return("Stored: user fact")
        allow(memory).to receive(:remember_preference).and_return("Stored: preference")
        allow(memory).to receive(:remember_context).and_return("Stored: context")
      end

      it "stores learned fact" do
        tool.execute(action: "store", category: "learned", key: "ruby", value: "Programming language")

        expect(memory).to have_received(:remember_learned).with("ruby", "Programming language")
      end

      it "stores user fact" do
        tool.execute(action: "store", category: "user", key: "name", value: "Alice")

        expect(memory).to have_received(:remember_user).with("name", "Alice")
      end

      it "stores preference" do
        tool.execute(action: "store", category: "preference", key: "theme", value: "dark")

        expect(memory).to have_received(:remember_preference).with("theme", "dark")
      end

      it "stores context" do
        tool.execute(action: "store", category: "context", key: "project", value: "Pocketrb")

        expect(memory).to have_received(:remember_context).with("project", "Pocketrb")
      end

      it "returns error without category" do
        result = tool.execute(action: "store", key: "test", value: "value")

        expect(result).to include("Error:")
        expect(result).to include("Category, key, and value required")
      end

      it "returns error without key" do
        result = tool.execute(action: "store", category: "learned", value: "value")

        expect(result).to include("Error:")
        expect(result).to include("Category, key, and value required")
      end

      it "returns error without value" do
        result = tool.execute(action: "store", category: "learned", key: "test")

        expect(result).to include("Error:")
        expect(result).to include("Category, key, and value required")
      end

      it "returns error for invalid category" do
        result = tool.execute(action: "store", category: "invalid", key: "test", value: "value")

        expect(result).to include("Error:")
        expect(result).to include("Invalid category")
      end
    end

    context "with recall action" do
      it "recalls relevant memories" do
        allow(memory).to receive(:relevant_context).and_return("Fact 1\nFact 2")

        result = tool.execute(action: "recall", query: "ruby")

        expect(memory).to have_received(:relevant_context).with("ruby", max_facts: 10)
        expect(result).to include("Relevant memories")
        expect(result).to include("Fact 1")
      end

      it "returns message when no memories found" do
        allow(memory).to receive(:relevant_context).and_return("")

        result = tool.execute(action: "recall", query: "unknown")

        expect(result).to include("No relevant memories found")
      end

      it "returns error without query" do
        result = tool.execute(action: "recall")

        expect(result).to include("Error:")
        expect(result).to include("Query required")
      end
    end

    context "with search action" do
      it "searches and formats results" do
        search_results = [
          { type: "learned", topic: "Ruby", content: "Programming language", date: "2024-01-01" },
          { type: "user", key: "name", value: "Alice", date: "2024-01-02" }
        ]
        allow(memory).to receive(:search).and_return(search_results)

        result = tool.execute(action: "search", query: "ruby")

        expect(memory).to have_received(:search).with("ruby")
        expect(result).to include("Found 2 memories")
        expect(result).to include("Ruby")
        expect(result).to include("Alice")
        expect(result).to include("2024-01-01")
      end

      it "handles empty search results" do
        allow(memory).to receive(:search).and_return([])

        result = tool.execute(action: "search", query: "nothing")

        expect(result).to include("No memories found matching: nothing")
      end

      it "returns error without query" do
        result = tool.execute(action: "search")

        expect(result).to include("Error:")
        expect(result).to include("Query required")
      end
    end

    context "with recent action" do
      it "shows recent events" do
        events = [
          { "timestamp" => "2024-01-01T10:00:00Z", "description" => "Event 1" },
          { "timestamp" => "2024-01-01T11:00:00Z", "description" => "Event 2" }
        ]
        allow(memory).to receive(:recent_events).and_return(events)

        result = tool.execute(action: "recent")

        expect(memory).to have_received(:recent_events).with(10)
        expect(result).to include("Recent events (2)")
        expect(result).to include("Event 1")
        expect(result).to include("Event 2")
      end

      it "handles no recent events" do
        allow(memory).to receive(:recent_events).and_return([])

        result = tool.execute(action: "recent")

        expect(result).to include("No recent events recorded")
      end
    end

    context "with stats action" do
      it "shows memory statistics" do
        stats = {
          learned_topics: 5,
          total_learned: 15,
          user_facts: 3,
          preferences: 2,
          context_items: 4,
          recent_events: 10
        }
        allow(memory).to receive(:stats).and_return(stats)

        result = tool.execute(action: "stats")

        expect(memory).to have_received(:stats)
        expect(result).to include("Memory Statistics")
        expect(result).to include("Learned topics: 5")
        expect(result).to include("User facts: 3")
        expect(result).to include("Preferences: 2")
        expect(result).to include("Context items: 4")
        expect(result).to include("Recent events: 10")
      end
    end

    context "with unknown action" do
      it "returns error" do
        result = tool.execute(action: "invalid")

        expect(result).to include("Error:")
        expect(result).to include("Unknown action")
      end
    end

    context "with execution error" do
      it "catches and returns error message" do
        allow(memory).to receive(:stats).and_raise(StandardError, "Test error")

        result = tool.execute(action: "stats")

        expect(result).to include("Error:")
        expect(result).to include("Memory error")
        expect(result).to include("Test error")
      end
    end
  end
end
