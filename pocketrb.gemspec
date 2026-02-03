# frozen_string_literal: true

require_relative "lib/pocketrb/version"

Gem::Specification.new do |spec|
  spec.name = "pocketrb"
  spec.version = Pocketrb::VERSION
  spec.authors = ["Maciej Mensfeld"]
  spec.email = ["contact@mensfeld.pl"]

  spec.summary = "Pocket-sized Ruby AI agent framework with multi-LLM support"
  spec.description = "Pocketrb is a Ruby AI agent framework featuring async message bus architecture, multi-LLM support (Claude, OpenRouter), multi-channel messaging (CLI, Telegram, WhatsApp), planning system, context compaction, and QMD memory via MCP."
  spec.homepage = "https://github.com/mensfeld/pocketrb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.glob("{bin,lib,exe}/**/*") + %w[LICENSE.txt README.md CHANGELOG.md]
  spec.bindir = "exe"
  spec.executables = ["pocketrb"]
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "async", "~> 2.0"
  spec.add_dependency "ruby_llm", "~> 1.0"
  spec.add_dependency "anthropic", "~> 0.3"
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "faraday-follow_redirects", "~> 0.3"
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "zeitwerk", "~> 2.6"
  spec.add_dependency "yaml", "~> 0.3"
  spec.add_dependency "json", "~> 2.7"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "tty-markdown", "~> 0.7"
  spec.add_dependency "pastel", "~> 0.8"
  spec.add_dependency "telegram-bot-ruby", "~> 2.0"

  # Optional dependencies (loaded on demand)
  # For WhatsApp bridge: gem install websocket-client-simple
  # For cron expressions: gem install fugit
end
