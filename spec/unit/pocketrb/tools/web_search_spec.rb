# frozen_string_literal: true

RSpec.describe Pocketrb::Tools::WebSearch do
  let(:context) { { brave_api_key: "test-api-key" } }
  let(:tool) { described_class.new(context) }

  # Disable VCR for unit tests, use WebMock stubs instead
  before do
    VCR.turn_off!(ignore_cassettes: true)
    WebMock.enable!
  end

  after do
    VCR.turn_on!
    WebMock.disable!
  end

  describe "#name" do
    it "returns web_search" do
      expect(tool.name).to eq("web_search")
    end
  end

  describe "#available?" do
    it "returns true when API key is available" do
      expect(tool.available?).to be true
    end

    it "returns false when API key is missing" do
      tool_without_key = described_class.new({})
      allow(ENV).to receive(:fetch).with("BRAVE_API_KEY", nil).and_return(nil)

      # available? returns nil (falsy) when key is missing, not explicitly false
      expect(tool_without_key).not_to be_available
    end

    it "returns false when API key is empty" do
      tool_with_empty = described_class.new(brave_api_key: "")
      expect(tool_with_empty.available?).to be false
    end

    it "uses ENV variable when context key is missing" do
      tool_without_context = described_class.new({})
      allow(ENV).to receive(:fetch).with("BRAVE_API_KEY", nil).and_return("env-key")

      expect(tool_without_context.available?).to be true
    end
  end

  describe "#execute" do
    let(:search_response) do
      {
        "web" => {
          "results" => [
            {
              "title" => "First Result",
              "url" => "https://example.com/1",
              "description" => "Description of the first result"
            },
            {
              "title" => "Second Result",
              "url" => "https://example.com/2",
              "description" => "Description of the second result"
            }
          ]
        }
      }
    end

    before do
      # Stub with query parameter matching
      stub_request(:get, %r{https://api.search.brave.com/res/v1/web/search})
        .to_return(status: 200, body: search_response.to_json, headers: { "Content-Type" => "application/json" })
    end

    context "with valid query" do
      it "performs search and returns formatted results" do
        result = tool.execute(query: "Ruby programming")

        expect(result).to include("Search results for: Ruby programming")
        expect(result).to include("First Result")
        expect(result).to include("https://example.com/1")
        expect(result).to include("Description of the first result")
      end

      it "includes result index numbers" do
        result = tool.execute(query: "test")

        expect(result).to include("1. First Result")
        expect(result).to include("2. Second Result")
      end

      it "sends API key in headers" do
        tool.execute(query: "test")

        expect(WebMock).to have_requested(:get, %r{https://api.search.brave.com/res/v1/web/search})
          .with(headers: { "X-Subscription-Token" => "test-api-key" })
      end

      it "sends query parameter" do
        tool.execute(query: "Ruby programming")

        expect(WebMock).to have_requested(:get, %r{https://api.search.brave.com/res/v1/web/search})
          .with(query: hash_including({ "q" => "Ruby programming" }))
      end
    end

    context "with count parameter" do
      it "uses default count of 5 when not specified" do
        tool.execute(query: "test")

        expect(WebMock).to have_requested(:get, %r{https://api.search.brave.com/res/v1/web/search})
          .with(query: hash_including({ "count" => "5" }))
      end

      it "uses custom count when specified" do
        tool.execute(query: "test", count: 10)

        expect(WebMock).to have_requested(:get, %r{https://api.search.brave.com/res/v1/web/search})
          .with(query: hash_including({ "count" => "10" }))
      end

      it "limits count to maximum of 20" do
        tool.execute(query: "test", count: 50)

        expect(WebMock).to have_requested(:get, %r{https://api.search.brave.com/res/v1/web/search})
          .with(query: hash_including({ "count" => "20" }))
      end

      it "ensures minimum count of 1" do
        tool.execute(query: "test", count: 0)

        expect(WebMock).to have_requested(:get, %r{https://api.search.brave.com/res/v1/web/search})
          .with(query: hash_including({ "count" => "1" }))
      end
    end

    context "without API key" do
      it "returns error" do
        tool_without_key = described_class.new({})
        allow(ENV).to receive(:fetch).with("BRAVE_API_KEY", nil).and_return(nil)

        result = tool_without_key.execute(query: "test")

        expect(result).to include("Error:")
        expect(result).to include("BRAVE_API_KEY")
      end
    end

    context "with empty results" do
      before do
        stub_request(:get, %r{https://api.search.brave.com/res/v1/web/search})
          .to_return(status: 200, body: { "web" => { "results" => [] } }.to_json,
                     headers: { "Content-Type" => "application/json" })
      end

      it "returns no results message" do
        result = tool.execute(query: "nonexistent query")

        expect(result).to eq("No results found for: nonexistent query")
      end
    end

    context "with missing web.results in response" do
      before do
        stub_request(:get, %r{https://api.search.brave.com/res/v1/web/search})
          .to_return(status: 200, body: {}.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "handles gracefully" do
        result = tool.execute(query: "test")

        expect(result).to include("No results found")
      end
    end

    context "with API errors" do
      it "handles HTTP error status" do
        stub_request(:get, %r{https://api.search.brave.com/res/v1/web/search})
          .to_return(status: 401, body: "Unauthorized")

        result = tool.execute(query: "test")

        expect(result).to include("Error:")
        expect(result).to include("Search failed: 401")
      end

      it "handles network errors" do
        stub_request(:get, %r{https://api.search.brave.com/res/v1/web/search})
          .to_raise(Faraday::ConnectionFailed)

        result = tool.execute(query: "test")

        expect(result).to include("Error:")
        expect(result).to include("Search request failed")
      end

      it "handles JSON parse errors" do
        stub_request(:get, %r{https://api.search.brave.com/res/v1/web/search})
          .to_return(status: 200, body: "invalid json")

        result = tool.execute(query: "test")

        expect(result).to include("Error:")
        expect(result).to include("Failed to parse")
      end
    end

    context "with result formatting" do
      it "handles results with missing fields" do
        response = {
          "web" => {
            "results" => [
              { "title" => "Only Title" },
              { "url" => "https://example.com" }
            ]
          }
        }
        stub_request(:get, %r{https://api.search.brave.com/res/v1/web/search})
          .to_return(status: 200, body: response.to_json, headers: { "Content-Type" => "application/json" })

        result = tool.execute(query: "test")

        expect(result).to include("Only Title")
        expect(result).to include("Untitled")
      end

      it "truncates long descriptions" do
        long_desc = "a" * 400
        response = {
          "web" => {
            "results" => [
              {
                "title" => "Test",
                "url" => "https://example.com",
                "description" => long_desc
              }
            ]
          }
        }
        stub_request(:get, %r{https://api.search.brave.com/res/v1/web/search})
          .to_return(status: 200, body: response.to_json, headers: { "Content-Type" => "application/json" })

        result = tool.execute(query: "test")

        # Description should be truncated to 300 chars
        expect(result).not_to include(long_desc)
        expect(result).to include("a" * 300)
      end
    end
  end
end
