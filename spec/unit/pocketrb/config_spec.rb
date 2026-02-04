# frozen_string_literal: true

RSpec.describe Pocketrb::Config do
  let(:workspace) { Dir.mktmpdir }
  let(:config) { described_class.new(workspace: workspace) }

  after do
    FileUtils.rm_rf(workspace)
  end

  describe "#initialize" do
    it "loads default configuration" do
      expect(config[:provider]).to eq("anthropic")
      expect(config[:model]).to eq("claude-sonnet-4-20250514")
      expect(config[:max_iterations]).to eq(50)
      expect(config[:heartbeat_interval]).to eq(1800)
    end

    it "creates config directory if workspace is provided" do
      config_dir = Pathname.new(workspace).join(".pocketrb")
      expect(config_dir).not_to be_directory

      config.save!
      expect(config_dir).to be_directory
    end

    it "loads existing config from workspace" do
      config_dir = Pathname.new(workspace).join(".pocketrb")
      FileUtils.mkdir_p(config_dir)
      File.write(config_dir.join("config.yml"), { provider: "openrouter", model: "test-model" }.to_yaml)

      new_config = described_class.new(workspace: workspace)
      expect(new_config[:provider]).to eq("openrouter")
      expect(new_config[:model]).to eq("test-model")
    end

    it "merges workspace config with defaults" do
      config_dir = Pathname.new(workspace).join(".pocketrb")
      FileUtils.mkdir_p(config_dir)
      File.write(config_dir.join("config.yml"), { provider: "custom" }.to_yaml)

      new_config = described_class.new(workspace: workspace)
      expect(new_config[:provider]).to eq("custom")
      expect(new_config[:max_iterations]).to eq(50) # default preserved
    end
  end

  describe "#[]" do
    it "returns config values by symbol key" do
      expect(config[:provider]).to eq("anthropic")
    end

    it "returns config values by string key" do
      expect(config["provider"]).to eq("anthropic")
    end

    it "returns nil for non-existent keys" do
      expect(config[:nonexistent]).to be_nil
    end
  end

  describe "#[]=" do
    it "sets config values" do
      config[:custom_key] = "custom_value"
      expect(config[:custom_key]).to eq("custom_value")
    end
  end

  describe "#get" do
    it "returns config value if it exists" do
      expect(config.get(:provider)).to eq("anthropic")
    end

    it "returns default if key doesn't exist" do
      expect(config.get(:nonexistent, "default")).to eq("default")
    end

    it "returns nil if key doesn't exist and no default provided" do
      expect(config.get(:nonexistent)).to be_nil
    end
  end

  describe "#set" do
    it "sets and saves config value" do
      config.set(:custom_key, "custom_value")
      expect(config[:custom_key]).to eq("custom_value")

      # Verify it was saved
      new_config = described_class.new(workspace: workspace)
      expect(new_config[:custom_key]).to eq("custom_value")
    end
  end

  describe "#key?" do
    it "returns true for existing keys (symbol)" do
      expect(config.key?(:provider)).to be true
    end

    it "returns true for existing keys (string)" do
      expect(config.key?("provider")).to be true
    end

    it "returns false for non-existent keys" do
      expect(config.key?(:nonexistent)).to be false
    end
  end

  describe "#provider_config" do
    it "returns provider configuration hash" do
      provider_config = config.provider_config
      expect(provider_config).to be_a(Hash)
      expect(provider_config[:model]).to eq("claude-sonnet-4-20250514")
    end

    it "includes API keys from config" do
      config[:anthropic_api_key] = "test-key"
      provider_config = config.provider_config
      expect(provider_config[:anthropic_api_key]).to eq("test-key")
    end

    it "prioritizes ENV variables over config for API keys" do
      config[:anthropic_api_key] = "config-key"
      ENV["ANTHROPIC_API_KEY"] = "env-key"

      provider_config = config.provider_config
      expect(provider_config[:anthropic_api_key]).to eq("env-key")

      ENV.delete("ANTHROPIC_API_KEY")
    end

    it "compacts nil values" do
      provider_config = config.provider_config
      expect(provider_config.values).not_to include(nil)
    end
  end

  describe "#save!" do
    it "saves config to workspace" do
      config[:custom_key] = "custom_value"
      config.save!

      config_file = Pathname.new(workspace).join(".pocketrb", "config.yml")
      expect(config_file).to exist

      saved_data = YAML.safe_load_file(config_file, permitted_classes: [Symbol])
      # Keys might be symbols or strings depending on YAML serialization
      expect(saved_data[:custom_key] || saved_data["custom_key"]).to eq("custom_value")
    end

    it "does nothing if no workspace is set" do
      config_without_workspace = described_class.new
      expect { config_without_workspace.save! }.not_to raise_error
    end
  end

  describe "#reload!" do
    it "reloads config from disk" do
      config[:custom_key] = "custom_value"
      config.save!

      # Modify config in memory
      config[:custom_key] = "modified_value"
      expect(config[:custom_key]).to eq("modified_value")

      # Reload should restore from disk
      config.reload!
      expect(config[:custom_key]).to eq("custom_value")
    end

    it "resets to defaults if no config file exists" do
      config[:provider] = "custom"
      config.reload!
      expect(config[:provider]).to eq("anthropic")
    end
  end

  describe "#merge!" do
    it "merges hash into config" do
      config.merge!(custom1: "value1", custom2: "value2")
      expect(config[:custom1]).to eq("value1")
      expect(config[:custom2]).to eq("value2")
    end

    it "overwrites existing values" do
      config[:provider] = "custom"
      expect(config[:provider]).to eq("custom")
    end
  end

  describe "#to_h" do
    it "returns config as hash" do
      hash = config.to_h
      expect(hash).to be_a(Hash)
      expect(hash[:provider]).to eq("anthropic")
    end

    it "returns a copy not the original" do
      hash = config.to_h
      hash[:provider] = "modified"
      expect(config[:provider]).to eq("anthropic")
    end
  end

  describe ".load" do
    it "creates new config for workspace" do
      loaded_config = described_class.load(workspace)
      expect(loaded_config).to be_a(described_class)
      expect(loaded_config[:provider]).to eq("anthropic")
    end
  end

  describe ".default" do
    it "returns singleton default config" do
      default1 = described_class.default
      default2 = described_class.default
      expect(default1).to be(default2)
    end
  end

  describe "ENV variable deprecation warnings" do
    let(:original_logger) { Pocketrb.logger }
    let(:log_output) { StringIO.new }

    before do
      Pocketrb.logger = Logger.new(log_output)
    end

    after do
      Pocketrb.logger = original_logger
      %w[POCKETRB_PROVIDER POCKETRB_MODEL ANTHROPIC_API_KEY].each { |k| ENV.delete(k) }
    end

    it "warns when POCKETRB_PROVIDER is used" do
      ENV["POCKETRB_PROVIDER"] = "test"
      described_class.new(workspace: workspace)
      expect(log_output.string).to include("DEPRECATION")
      expect(log_output.string).to include("POCKETRB_PROVIDER")
    end

    it "warns when ANTHROPIC_API_KEY is used" do
      ENV["ANTHROPIC_API_KEY"] = "test-key"
      config = described_class.new(workspace: workspace)
      config.provider_config
      expect(log_output.string).to include("DEPRECATION")
      expect(log_output.string).to include("ANTHROPIC_API_KEY")
    end

    it "only warns once per ENV variable" do
      ENV["POCKETRB_PROVIDER"] = "test"
      config = described_class.new(workspace: workspace)
      config.reload!
      config.reload!
      # Should only warn once
      expect(log_output.string.scan(/DEPRECATION.*POCKETRB_PROVIDER/).count).to eq(1)
    end

    it "respects ENV variable values" do
      ENV["POCKETRB_MODEL"] = "custom-model"
      config = described_class.new(workspace: workspace)
      expect(config[:model]).to eq("custom-model")
    end
  end

  describe "ENV variable overrides" do
    after do
      %w[POCKETRB_PROVIDER POCKETRB_MODEL POCKETRB_MAX_ITERATIONS
         POCKETRB_AUTONOMOUS MCP_ENDPOINT POCKETRB_LOG_LEVEL].each { |k| ENV.delete(k) }
    end

    it "overrides provider from ENV" do
      ENV["POCKETRB_PROVIDER"] = "openrouter"
      config = described_class.new(workspace: workspace)
      expect(config[:provider]).to eq("openrouter")
    end

    it "overrides model from ENV" do
      ENV["POCKETRB_MODEL"] = "custom-model"
      config = described_class.new(workspace: workspace)
      expect(config[:model]).to eq("custom-model")
    end

    it "overrides max_iterations from ENV" do
      ENV["POCKETRB_MAX_ITERATIONS"] = "100"
      config = described_class.new(workspace: workspace)
      expect(config[:max_iterations]).to eq(100)
    end

    it "overrides autonomous from ENV (true)" do
      ENV["POCKETRB_AUTONOMOUS"] = "1"
      config = described_class.new(workspace: workspace)
      expect(config[:autonomous]).to be true
    end

    it "overrides autonomous from ENV (string true)" do
      ENV["POCKETRB_AUTONOMOUS"] = "true"
      config = described_class.new(workspace: workspace)
      expect(config[:autonomous]).to be true
    end

    it "overrides mcp_endpoint from ENV" do
      ENV["MCP_ENDPOINT"] = "http://custom:8080"
      config = described_class.new(workspace: workspace)
      expect(config[:mcp_endpoint]).to eq("http://custom:8080")
    end
  end
end
