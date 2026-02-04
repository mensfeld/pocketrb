# frozen_string_literal: true

RSpec.describe Pocketrb::Tools::WebFetch do
  let(:workspace) { Pathname.new(Dir.mktmpdir) }
  let(:tool) { described_class.new(workspace: workspace) }

  # Disable VCR for these tests since we're using WebMock
  around do |example|
    VCR.turned_off do
      example.run
    end
  end

  after do
    FileUtils.rm_rf(workspace)
  end

  describe "#name" do
    it "returns web_fetch" do
      expect(tool.name).to eq("web_fetch")
    end
  end

  describe "#execute" do
    context "with valid HTML page" do
      let(:html_content) do
        <<~HTML
          <!DOCTYPE html>
          <html>
            <head><title>Test Page</title></head>
            <body>
              <h1>Welcome</h1>
              <p>This is a test page.</p>
              <script>alert('ignore');</script>
            </body>
          </html>
        HTML
      end

      before do
        stub_request(:get, "https://example.com/page")
          .to_return(status: 200, body: html_content, headers: { "Content-Type" => "text/html" })
      end

      it "fetches and extracts HTML content" do
        result = tool.execute(url: "https://example.com/page")

        expect(result).to include("Welcome")
        expect(result).to include("This is a test page")
        expect(result).not_to include("<html>")
        expect(result).not_to include("script")
      end

      it "adds https to URLs without scheme" do
        stub_request(:get, "https://example.com/test")
          .to_return(status: 200, body: "<html><body>Test</body></html>")

        result = tool.execute(url: "example.com/test")

        expect(result).to include("Test")
      end
    end

    context "with JSON content" do
      let(:json_content) { '{"message":"Hello","count":42}' }

      before do
        stub_request(:get, "https://api.example.com/data")
          .to_return(status: 200, body: json_content, headers: { "Content-Type" => "application/json" })
      end

      it "fetches and formats JSON" do
        result = tool.execute(url: "https://api.example.com/data")

        expect(result).to include('"message": "Hello"')
        expect(result).to include('"count": 42')
      end
    end

    context "with plain text content" do
      let(:text_content) { "This is plain text content." }

      before do
        stub_request(:get, "https://example.com/text")
          .to_return(status: 200, body: text_content, headers: { "Content-Type" => "text/plain" })
      end

      it "returns text as-is" do
        result = tool.execute(url: "https://example.com/text")

        expect(result).to eq(text_content)
      end
    end

    context "with large content" do
      let(:large_content) { "x" * 600_000 }

      before do
        stub_request(:get, "https://example.com/large")
          .to_return(status: 200, body: large_content)
      end

      it "truncates content at MAX_CONTENT_SIZE" do
        result = tool.execute(url: "https://example.com/large")

        expect(result.length).to be < large_content.length
        expect(result).to include("Content truncated")
        expect(result).to include("500000 characters")
      end
    end

    context "with redirects" do
      before do
        stub_request(:get, "https://example.com/redirect")
          .to_return(status: 301, headers: { "Location" => "https://example.com/final" })

        stub_request(:get, "https://example.com/final")
          .to_return(status: 200, body: "Final content")
      end

      it "follows redirects" do
        result = tool.execute(url: "https://example.com/redirect")

        expect(result).to eq("Final content")
      end
    end

    context "with HTTP errors" do
      it "handles 404 errors" do
        stub_request(:get, "https://example.com/notfound")
          .to_return(status: 404)

        result = tool.execute(url: "https://example.com/notfound")

        expect(result).to include("Error:")
        expect(result).to include("Failed to fetch URL")
        expect(result).to include("404")
      end

      it "handles 500 errors" do
        stub_request(:get, "https://example.com/error")
          .to_return(status: 500)

        result = tool.execute(url: "https://example.com/error")

        expect(result).to include("Error:")
        expect(result).to include("500")
      end
    end

    context "with invalid URLs" do
      it "returns error for invalid URL format" do
        result = tool.execute(url: "not a url")

        expect(result).to include("Error:")
        expect(result).to include("Invalid URL")
      end

      it "returns error for completely invalid URL" do
        result = tool.execute(url: "ht!tp://exam ple")

        expect(result).to include("Error:")
        expect(result).to include("Invalid URL")
      end
    end

    context "with network errors" do
      it "handles connection failures" do
        stub_request(:get, "https://example.com/timeout")
          .to_raise(Faraday::ConnectionFailed)

        result = tool.execute(url: "https://example.com/timeout")

        expect(result).to include("Error:")
        expect(result).to include("Request failed")
      end

      it "handles timeout errors" do
        stub_request(:get, "https://example.com/slow")
          .to_raise(Faraday::TimeoutError)

        result = tool.execute(url: "https://example.com/slow")

        expect(result).to include("Error:")
        expect(result).to include("Request failed")
      end
    end

    context "with HTML entity decoding" do
      let(:html_with_entities) do
        <<~HTML
          <html><body>
            <p>Hello &amp; goodbye &lt;world&gt;</p>
            <p>&quot;Quote&quot; and &#8217; apostrophe</p>
          </body></html>
        HTML
      end

      before do
        stub_request(:get, "https://example.com/entities")
          .to_return(status: 200, body: html_with_entities)
      end

      it "decodes HTML entities" do
        result = tool.execute(url: "https://example.com/entities")

        expect(result).to include("Hello & goodbye <world>")
        expect(result).to include('"Quote"')
      end
    end

    context "with HTML tags to strip" do
      let(:html_with_tags) do
        <<~HTML
          <html>
            <head><title>Test</title></head>
            <script>alert('bad');</script>
            <style>.hidden { display: none; }</style>
            <nav>Navigation</nav>
            <body>
              <p>Main content</p>
            </body>
            <footer>Footer</footer>
          </html>
        HTML
      end

      before do
        stub_request(:get, "https://example.com/tags")
          .to_return(status: 200, body: html_with_tags)
      end

      it "strips script, style, nav, footer, and head tags" do
        result = tool.execute(url: "https://example.com/tags")

        expect(result).to include("Main content")
        expect(result).not_to include("alert")
        expect(result).not_to include("display: none")
        expect(result).not_to include("Navigation")
        expect(result).not_to include("Footer")
      end
    end

    context "with invalid JSON" do
      before do
        stub_request(:get, "https://example.com/badjson")
          .to_return(status: 200, body: "{invalid json}")
      end

      it "returns raw content when JSON parsing fails" do
        result = tool.execute(url: "https://example.com/badjson")

        expect(result).to eq("{invalid json}")
      end
    end
  end
end
