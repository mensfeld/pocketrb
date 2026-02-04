# frozen_string_literal: true

RSpec.describe Pocketrb::Memory do
  let(:workspace) { Dir.mktmpdir }
  let(:memory) { described_class.new(workspace: workspace) }

  after do
    FileUtils.rm_rf(workspace)
  end

  describe "#initialize" do
    it "creates memory directory if it doesn't exist" do
      memory # instantiate memory object
      expect(Pathname.new(workspace).join("memory")).to be_directory
    end

    it "loads existing facts.json if present" do
      facts_file = Pathname.new(workspace).join("memory", "facts.json")
      FileUtils.mkdir_p(facts_file.dirname)
      File.write(facts_file, JSON.pretty_generate({
                                                    "learned" => { "ruby" => [{ "info" => "Ruby is awesome",
                                                                                "learned_at" => "2026-01-01T00:00:00Z" }] },
                                                    "user" => {},
                                                    "preferences" => {},
                                                    "context" => {}
                                                  }))

      mem = described_class.new(workspace: workspace)
      expect(mem.recall_learned("ruby")).to eq([{ "info" => "Ruby is awesome",
                                                  "learned_at" => "2026-01-01T00:00:00Z" }])
    end

    it "initializes with empty data if no files exist" do
      expect(memory.stats[:learned_topics]).to eq(0)
      expect(memory.stats[:recent_events]).to eq(0)
    end

    context "when facts.json is malformed" do
      it "raises ConfigurationError with helpful message" do
        facts_file = Pathname.new(workspace).join("memory", "facts.json")
        FileUtils.mkdir_p(facts_file.dirname)
        File.write(facts_file, '{ "invalid": json syntax }')

        expect do
          described_class.new(workspace: workspace)
        end.to raise_error(Pocketrb::ConfigurationError, /Invalid JSON in.*facts\.json/)
      end

      it "includes file path in error message" do
        facts_file = Pathname.new(workspace).join("memory", "facts.json")
        FileUtils.mkdir_p(facts_file.dirname)
        File.write(facts_file, "{ broken")

        expect do
          described_class.new(workspace: workspace)
        end.to raise_error(Pocketrb::ConfigurationError, /facts\.json/)
      end

      it "includes content preview in error message" do
        facts_file = Pathname.new(workspace).join("memory", "facts.json")
        FileUtils.mkdir_p(facts_file.dirname)
        File.write(facts_file, '{ "this is": "malformed JSON"')

        expect do
          described_class.new(workspace: workspace)
        end.to raise_error(Pocketrb::ConfigurationError, /Content preview:/)
      end
    end

    context "when recent.json is malformed" do
      it "raises ConfigurationError" do
        recent_file = Pathname.new(workspace).join("memory", "recent.json")
        FileUtils.mkdir_p(recent_file.dirname)
        # Create valid facts.json first
        File.write(recent_file.dirname.join("facts.json"), JSON.pretty_generate({
                                                                                  "learned" => {},
                                                                                  "user" => {},
                                                                                  "preferences" => {},
                                                                                  "context" => {}
                                                                                }))
        File.write(recent_file, "[ invalid json ]")

        expect do
          described_class.new(workspace: workspace)
        end.to raise_error(Pocketrb::ConfigurationError, /Invalid JSON in.*recent\.json/)
      end
    end
  end

  describe "#remember_learned" do
    it "stores learned information" do
      result = memory.remember_learned("ruby", "Ruby is dynamically typed")
      expect(result).to eq("Remembered: learned about ruby")
      expect(memory.recall_learned("ruby")).to be_an(Array)
      expect(memory.recall_learned("ruby").first["info"]).to eq("Ruby is dynamically typed")
    end

    it "appends to existing topic" do
      memory.remember_learned("ruby", "First fact")
      memory.remember_learned("ruby", "Second fact")
      facts = memory.recall_learned("ruby")
      expect(facts.size).to eq(2)
      expect(facts[0]["info"]).to eq("First fact")
      expect(facts[1]["info"]).to eq("Second fact")
    end

    it "includes timestamp" do
      memory.remember_learned("ruby", "Test fact")
      fact = memory.recall_learned("ruby").first
      expect(fact["learned_at"]).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)
    end
  end

  describe "#remember_user" do
    it "stores user information" do
      result = memory.remember_user("name", "Alice")
      expect(result).to eq("Remembered: user's name is Alice")
      expect(memory.recall_user("name")["value"]).to eq("Alice")
    end

    it "updates existing user info" do
      memory.remember_user("name", "Alice")
      memory.remember_user("name", "Bob")
      expect(memory.recall_user("name")["value"]).to eq("Bob")
    end

    it "returns all user info when no key specified" do
      memory.remember_user("name", "Alice")
      memory.remember_user("age", "30")
      all_user = memory.recall_user
      expect(all_user.keys).to contain_exactly("name", "age")
    end
  end

  describe "#remember_preference" do
    it "stores preferences" do
      result = memory.remember_preference("theme", "dark")
      expect(result).to eq("Remembered preference: theme = dark")
      expect(memory.recall_preferences("theme")["value"]).to eq("dark")
    end
  end

  describe "#remember_context" do
    it "stores context information" do
      result = memory.remember_context("project", "pocketrb")
      expect(result).to eq("Remembered: project")
    end
  end

  describe "#add_event" do
    it "adds recent events" do
      memory.add_event("User logged in")
      events = memory.recent_events
      expect(events.size).to eq(1)
      expect(events.first["description"]).to eq("User logged in")
    end

    it "limits to MAX_RECENT events" do
      (described_class::MAX_RECENT + 10).times do |i|
        memory.add_event("Event #{i}")
      end
      expect(memory.recent_events(100).size).to eq(described_class::MAX_RECENT)
    end

    it "keeps most recent events" do
      memory.add_event("Old event")
      memory.add_event("New event")
      events = memory.recent_events
      expect(events.first["description"]).to eq("New event")
      expect(events.last["description"]).to eq("Old event")
    end

    it "supports event categories" do
      memory.add_event("Login", category: "auth")
      event = memory.recent_events.first
      expect(event["category"]).to eq("auth")
    end
  end

  describe "#relevant_context" do
    before do
      memory.remember_user("name", "Alice")
      memory.remember_preference("theme", "dark")
      memory.remember_learned("ruby", "Ruby is a programming language")
      memory.add_event("User asked about Ruby")
    end

    it "includes user info" do
      context = memory.relevant_context("hello")
      expect(context).to include("USER: name: Alice")
    end

    it "includes preferences" do
      context = memory.relevant_context("hello")
      expect(context).to include("PREFERENCES: theme: dark")
    end

    it "includes matching learned facts" do
      context = memory.relevant_context("tell me about ruby")
      expect(context).to include("KNOWN ABOUT ruby: Ruby is a programming language")
    end

    it "includes recent events" do
      context = memory.relevant_context("hello")
      expect(context).to include("RECENT:")
      expect(context).to include("User asked about Ruby")
    end

    it "limits facts to max_facts parameter" do
      5.times { |i| memory.remember_learned("topic#{i}", "Fact #{i}") }
      context = memory.relevant_context("topic0 topic1 topic2 topic3 topic4", max_facts: 2)
      # Should only include 2 facts
      fact_count = context.scan("KNOWN ABOUT").size
      expect(fact_count).to eq(2)
    end
  end

  describe "#search" do
    before do
      memory.remember_learned("ruby", "Ruby programming language")
      memory.remember_user("language", "Ruby")
      memory.remember_preference("editor", "vim")
    end

    it "searches across learned facts" do
      results = memory.search("ruby")
      expect(results).not_to be_empty
      learned = results.find { |r| r[:type] == "learned" }
      expect(learned[:content]).to eq("Ruby programming language")
    end

    it "searches across user info" do
      results = memory.search("language")
      user_result = results.find { |r| r[:type] == "user" }
      expect(user_result[:value]).to eq("Ruby")
    end

    it "searches across preferences" do
      results = memory.search("vim")
      pref = results.find { |r| r[:type] == "preference" }
      expect(pref[:value]).to eq("vim")
    end

    it "returns empty array when no matches" do
      results = memory.search("nonexistent")
      expect(results).to eq([])
    end
  end

  describe "#stats" do
    it "returns memory statistics" do
      memory.remember_learned("ruby", "Fact 1")
      memory.remember_learned("ruby", "Fact 2")
      memory.remember_user("name", "Alice")
      memory.add_event("Test event")

      stats = memory.stats
      expect(stats[:learned_topics]).to eq(1)
      expect(stats[:total_learned]).to eq(2)
      expect(stats[:user_facts]).to eq(1)
      expect(stats[:recent_events]).to eq(1)
    end
  end

  describe "#dump_all" do
    it "returns all memory data" do
      memory.remember_learned("ruby", "Test")
      memory.add_event("Event")

      dump = memory.dump_all
      expect(dump).to have_key("facts")
      expect(dump).to have_key("recent")
      expect(dump["facts"]["learned"]["ruby"]).not_to be_empty
      expect(dump["recent"]).not_to be_empty
    end
  end

  describe "persistence" do
    it "persists learned facts across instances" do
      memory.remember_learned("ruby", "Ruby is awesome")
      memory2 = described_class.new(workspace: workspace)
      expect(memory2.recall_learned("ruby").first["info"]).to eq("Ruby is awesome")
    end

    it "persists recent events across instances" do
      memory.add_event("Test event")
      memory2 = described_class.new(workspace: workspace)
      expect(memory2.recent_events.first["description"]).to eq("Test event")
    end

    it "persists user info across instances" do
      memory.remember_user("name", "Alice")
      memory2 = described_class.new(workspace: workspace)
      expect(memory2.recall_user("name")["value"]).to eq("Alice")
    end
  end
end
