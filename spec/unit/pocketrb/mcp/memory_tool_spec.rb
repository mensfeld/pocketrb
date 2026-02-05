# frozen_string_literal: true

RSpec.describe Pocketrb::MCP::MemoryTool do
  let(:mcp_client) { instance_double(Pocketrb::MCP::Client) }
  let(:context) { { mcp_client: mcp_client } }
  let(:tool) { described_class.new(context) }

  describe "#initialize" do
    it "stores MCP client from context" do
      expect(tool.instance_variable_get(:@client)).to eq(mcp_client)
    end

    it "creates new client if not provided" do
      tool_without_client = described_class.new({})
      expect(tool_without_client.instance_variable_get(:@client)).to be_a(Pocketrb::MCP::Client)
    end
  end

  describe "#name" do
    it "returns memory" do
      expect(tool.name).to eq("memory")
    end
  end

  describe "#description" do
    it "describes memory interaction functionality" do
      desc = tool.description
      expect(desc).to include("memory")
      expect(desc).to include("Search")
      expect(desc).to include("store")
    end
  end

  describe "#parameters" do
    it "requires action parameter" do
      expect(tool.parameters[:required]).to eq(["action"])
    end

    it "includes action enum with search and store" do
      action_prop = tool.parameters[:properties][:action]
      expect(action_prop[:enum]).to contain_exactly("search", "store")
    end

    it "includes query parameter for search" do
      expect(tool.parameters[:properties]).to have_key(:query)
    end

    it "includes content parameter for store" do
      expect(tool.parameters[:properties]).to have_key(:content)
    end

    it "includes tags parameter for store" do
      tags_prop = tool.parameters[:properties][:tags]
      expect(tags_prop[:type]).to eq("array")
    end

    it "includes limit parameter for search" do
      expect(tool.parameters[:properties]).to have_key(:limit)
    end
  end

  describe "#available?" do
    it "returns true when client is connected" do
      allow(mcp_client).to receive(:connected?).and_return(true)

      expect(tool.available?).to be true
    end

    it "tries to connect if not connected" do
      allow(mcp_client).to receive_messages(connected?: false, connect: true)

      expect(tool.available?).to be true
      expect(mcp_client).to have_received(:connect)
    end

    it "returns false on connection error" do
      allow(mcp_client).to receive(:connected?).and_raise(StandardError, "Connection failed")

      expect(tool.available?).to be false
    end
  end

  describe "#execute" do
    context "with search action" do
      it "performs search with query" do
        allow(mcp_client).to receive(:search).and_return([{ "content" => "Result" }])

        result = tool.execute(action: "search", query: "test query", limit: 5)

        expect(mcp_client).to have_received(:search).with(query: "test query", limit: 5)
        expect(result).to include("Memory search results")
        expect(result).to include("Result")
      end

      it "returns error when query is missing" do
        result = tool.execute(action: "search")

        expect(result).to include("Error:")
        expect(result).to include("Query is required")
      end

      it "returns error when query is empty" do
        result = tool.execute(action: "search", query: "")

        expect(result).to include("Error:")
        expect(result).to include("Query is required")
      end

      it "returns message when no results found" do
        allow(mcp_client).to receive(:search).and_return([])

        result = tool.execute(action: "search", query: "nonexistent")

        expect(result).to include("No relevant memories found")
      end

      it "handles MCP errors" do
        allow(mcp_client).to receive(:search).and_raise(Pocketrb::MCPError, "API error")

        result = tool.execute(action: "search", query: "test")

        expect(result).to include("Error:")
        expect(result).to include("Memory search failed")
      end
    end

    context "with store action" do
      it "stores content to memory" do
        allow(mcp_client).to receive(:store).and_return(true)

        result = tool.execute(action: "store", content: "Important fact")

        expect(mcp_client).to have_received(:store).with(
          content: "Important fact",
          metadata: hash_including(:timestamp, :source)
        )
        expect(result).to include("Stored to memory")
      end

      it "includes tags in metadata" do
        allow(mcp_client).to receive(:store).and_return(true)

        tool.execute(action: "store", content: "Fact", tags: %w[important work])

        expect(mcp_client).to have_received(:store).with(
          content: "Fact",
          metadata: hash_including(:tags)
        )
      end

      it "includes timestamp in metadata" do
        allow(mcp_client).to receive(:store).and_return(true)

        tool.execute(action: "store", content: "Fact")

        expect(mcp_client).to have_received(:store).with(
          content: "Fact",
          metadata: hash_including(:timestamp)
        )
      end

      it "includes source in metadata" do
        allow(mcp_client).to receive(:store).and_return(true)

        tool.execute(action: "store", content: "Fact")

        expect(mcp_client).to have_received(:store).with(
          content: "Fact",
          metadata: hash_including(source: "pocketrb")
        )
      end

      it "returns error when content is missing" do
        result = tool.execute(action: "store")

        expect(result).to include("Error:")
        expect(result).to include("Content is required")
      end

      it "returns error when content is empty" do
        result = tool.execute(action: "store", content: "")

        expect(result).to include("Error:")
        expect(result).to include("Content is required")
      end

      it "truncates long content in success message" do
        allow(mcp_client).to receive(:store).and_return(true)
        long_content = "x" * 200

        result = tool.execute(action: "store", content: long_content)

        expect(result).to include("...")
      end

      it "returns error when store fails" do
        allow(mcp_client).to receive(:store).and_return(false)

        result = tool.execute(action: "store", content: "Fact")

        expect(result).to include("Error:")
        expect(result).to include("Failed to store")
      end

      it "handles MCP errors" do
        allow(mcp_client).to receive(:store).and_raise(Pocketrb::MCPError, "API error")

        result = tool.execute(action: "store", content: "Fact")

        expect(result).to include("Error:")
        expect(result).to include("Memory store failed")
      end
    end

    context "with unknown action" do
      it "returns error" do
        result = tool.execute(action: "invalid")

        expect(result).to include("Error:")
        expect(result).to include("Unknown action")
      end
    end
  end

  describe "result formatting" do
    context "with string results" do
      it "formats string response" do
        allow(mcp_client).to receive(:search).and_return("Direct text response")

        result = tool.execute(action: "search", query: "test")

        expect(result).to include("Direct text response")
      end
    end

    context "with array results" do
      it "formats array of results" do
        results = [
          { "content" => "First result" },
          { "content" => "Second result" }
        ]
        allow(mcp_client).to receive(:search).and_return(results)

        result = tool.execute(action: "search", query: "test")

        expect(result).to include("1. First result")
        expect(result).to include("2. Second result")
      end

      it "includes score when available" do
        results = [{ "content" => "Result", "score" => 0.95 }]
        allow(mcp_client).to receive(:search).and_return(results)

        result = tool.execute(action: "search", query: "test")

        expect(result).to include("Score: 0.95")
      end

      it "includes tags when available" do
        results = [{ "content" => "Result", "tags" => %w[important work] }]
        allow(mcp_client).to receive(:search).and_return(results)

        result = tool.execute(action: "search", query: "test")

        expect(result).to include("Tags: important, work")
      end

      it "truncates long content" do
        long_content = "x" * 1000
        results = [{ "content" => long_content }]
        allow(mcp_client).to receive(:search).and_return(results)

        result = tool.execute(action: "search", query: "test")

        expect(result.length).to be < long_content.length + 100
      end
    end

    context "with hash results" do
      it "formats hash with results key" do
        response = {
          "results" => [
            { "content" => "Result 1" },
            { "content" => "Result 2" }
          ]
        }
        allow(mcp_client).to receive(:search).and_return(response)

        result = tool.execute(action: "search", query: "test")

        expect(result).to include("1. Result 1")
        expect(result).to include("2. Result 2")
      end

      it "handles nested tags in metadata" do
        response = {
          "results" => [
            { "content" => "Result", "metadata" => { "tags" => ["tag1"] } }
          ]
        }
        allow(mcp_client).to receive(:search).and_return(response)

        result = tool.execute(action: "search", query: "test")

        expect(result).to include("Tags: tag1")
      end
    end
  end
end
