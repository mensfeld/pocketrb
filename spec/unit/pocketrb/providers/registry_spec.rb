# frozen_string_literal: true

RSpec.describe Pocketrb::Providers::Registry do
  let(:registry) { described_class.new }

  describe "#initialize" do
    it "registers default providers" do
      expect(registry.available).to include(
        :anthropic,
        :openrouter,
        :ruby_llm,
        :claude_cli,
        :claude_max_proxy
      )
    end

    it "starts with 5 default providers" do
      expect(registry.available.length).to eq(5)
    end
  end

  describe "#register" do
    let(:mock_provider) { Class.new { def initialize(config); end } }

    it "registers a provider with symbol name" do
      registry.register(:test_provider, mock_provider)

      expect(registry.available).to include(:test_provider)
    end

    it "registers a provider with string name" do
      registry.register("test_provider", mock_provider)

      expect(registry.available).to include(:test_provider)
    end

    it "overwrites existing provider" do
      original = Class.new { def initialize(config); end }
      replacement = Class.new { def initialize(config); end }

      registry.register(:test, original)
      registry.register(:test, replacement)

      provider = registry.get(:test, {})

      expect(provider).to be_a(replacement)
    end
  end

  describe "#get" do
    let(:mock_provider_class) do
      Class.new do
        attr_reader :config

        def initialize(config)
          @config = config
        end
      end
    end

    before do
      registry.register(:test, mock_provider_class)
    end

    it "returns provider instance with config" do
      config = { api_key: "test123" }
      provider = registry.get(:test, config)

      expect(provider).to be_a(mock_provider_class)
      expect(provider.config).to eq(config)
    end

    it "accepts string provider name" do
      provider = registry.get("test", {})

      expect(provider).to be_a(mock_provider_class)
    end

    it "raises error for unknown provider" do
      expect do
        registry.get(:nonexistent, {})
      end.to raise_error(Pocketrb::ConfigurationError, /Unknown provider: nonexistent/)
    end

    it "passes empty config by default" do
      provider = registry.get(:test)

      expect(provider.config).to eq({})
    end
  end

  describe "#available" do
    it "returns array of provider names" do
      expect(registry.available).to be_an(Array)
      expect(registry.available.first).to be_a(Symbol)
    end

    it "includes newly registered providers" do
      mock_provider = Class.new { def initialize(config); end }
      registry.register(:new_provider, mock_provider)

      expect(registry.available).to include(:new_provider)
    end
  end

  describe ".instance" do
    it "returns singleton instance" do
      instance1 = described_class.instance
      instance2 = described_class.instance

      expect(instance1).to be(instance2)
    end

    it "has default providers registered" do
      expect(described_class.instance.available).to include(:anthropic)
    end
  end

  describe ".register" do
    it "delegates to singleton instance" do
      mock_provider = Class.new { def initialize(config); end }
      described_class.register(:class_test, mock_provider)

      expect(described_class.instance.available).to include(:class_test)
    end
  end

  describe ".get" do
    let(:mock_provider_class) do
      Class.new do
        def initialize(config); end
      end
    end

    before do
      described_class.register(:test, mock_provider_class)
    end

    it "delegates to singleton instance" do
      provider = described_class.get(:test, {})

      expect(provider).to be_a(mock_provider_class)
    end
  end

  describe ".available" do
    it "delegates to singleton instance" do
      providers = described_class.available

      expect(providers).to be_an(Array)
      expect(providers).to include(:anthropic)
    end
  end
end
