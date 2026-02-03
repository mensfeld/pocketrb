# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  add_group "Bus", "lib/pocketrb/bus"
  add_group "Providers", "lib/pocketrb/providers"
  add_group "Tools", "lib/pocketrb/tools"
  add_group "Agent", "lib/pocketrb/agent"
  add_group "Session", "lib/pocketrb/session"
  add_group "MCP", "lib/pocketrb/mcp"
  add_group "Skills", "lib/pocketrb/skills"
  add_group "Planning", "lib/pocketrb/planning"
  add_group "Channels", "lib/pocketrb/channels"
end

ENV["POCKETRB_EAGER_LOAD"] = "1"
require "tmpdir"
require "pocketrb"
require "webmock/rspec"
require "vcr"

# Disable external connections in tests
WebMock.disable_net_connect!(allow_localhost: true)

VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV["ANTHROPIC_API_KEY"] }
  config.filter_sensitive_data("<OPENROUTER_API_KEY>") { ENV["OPENROUTER_API_KEY"] }
  config.filter_sensitive_data("<BRAVE_API_KEY>") { ENV["BRAVE_API_KEY"] }
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = true

  config.default_formatter = "doc" if config.files_to_run.one?

  config.order = :random
  Kernel.srand config.seed
end

# Test helpers
module TestHelpers
  def temp_workspace
    @temp_workspace ||= Pathname.new(Dir.mktmpdir("pocketrb-test"))
  end

  def cleanup_temp_workspace
    FileUtils.rm_rf(@temp_workspace) if @temp_workspace&.exist?
    @temp_workspace = nil
  end
end

RSpec.configure do |config|
  config.include TestHelpers

  config.after(:each) do
    cleanup_temp_workspace
  end
end
