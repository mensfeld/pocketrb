# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "pocketrb/version"

Gem::Specification.new do |spec|
  spec.name = "pocketrb"
  spec.version = Pocketrb::VERSION
  spec.platform = Gem::Platform::RUBY
  spec.authors = ["Maciej Mensfeld"]
  spec.email = %w[maciej@mensfeld.pl]
  spec.homepage = "https://github.com/mensfeld/pocketrb"
  spec.licenses = %w[MIT]
  spec.summary = "Pocket-sized Ruby AI agent framework with multi-LLM support"
  spec.description = <<-DESC
    Pocketrb is a Ruby AI agent framework featuring async message bus architecture,
    multi-LLM support (Claude, OpenRouter, RubyLLM), multi-channel messaging
    (CLI, Telegram, WhatsApp), planning system, context compaction, and simple
    JSON-based memory with keyword matching.
  DESC

  spec.required_ruby_version = ">= 3.2.0"

  # Runtime dependencies
  spec.add_dependency "anthropic", "~> 0.3"
  spec.add_dependency "async", "~> 2.0"
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "faraday-follow_redirects", "~> 0.3"
  spec.add_dependency "json", "~> 2.7"
  spec.add_dependency "pastel", "~> 0.8"
  spec.add_dependency "playwright-ruby-client", "~> 1.58"
  spec.add_dependency "ruby_llm", "~> 1.0"
  spec.add_dependency "telegram-bot-ruby", "~> 2.0"
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "tty-markdown", "~> 0.7"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "yaml", "~> 0.3"
  spec.add_dependency "zeitwerk", "~> 2.6"

  spec.files = `git ls-files -z`.split("\x0").select do |f|
    f.match(%r{^(lib|exe)/}) || %w[LICENSE.txt CHANGELOG.md README.md pocketrb.gemspec].include?(f)
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = %w[lib]

  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/mensfeld/pocketrb/issues",
    "changelog_uri" => "https://github.com/mensfeld/pocketrb/blob/master/CHANGELOG.md",
    "homepage_uri" => "https://github.com/mensfeld/pocketrb",
    "source_code_uri" => "https://github.com/mensfeld/pocketrb/tree/master",
    "rubygems_mfa_required" => "true"
  }
end

# Optional dependencies (loaded on demand)
# For WhatsApp bridge: gem install websocket-client-simple
# For cron expressions: gem install fugit
