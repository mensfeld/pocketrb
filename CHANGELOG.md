# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Removed

- Maintenance: Remove the `ANTHROPIC_OAUTH_TOKEN` (`anthropic_oauth_token`) authentication from the `anthropic` provider and the `claude_max_proxy` provider. Anthropic's terms do not permit third-party apps to route requests through Claude subscription (Free, Pro, Max) credentials. The `anthropic` provider now requires `ANTHROPIC_API_KEY`; for subscription use, use the `claude_cli` provider, which runs the official `claude` binary

### Fixed

- Fix: `pocketrb gateway` runs its channels at the same time, so WhatsApp, cron and heartbeat start when Telegram is enabled, and a failing channel is logged without stopping the others. Each channel consumes its own outbound messages (`MessageBus#consume_outbound(channel)`), so replies reach WhatsApp while Telegram runs; a reply for a channel that is not running (or any reply when no channel runs) is dropped with a warning. Without `--whatsapp-bridge` and without the `websocket-client-simple` gem, it skips WhatsApp with a warning instead of exiting; an explicit `--whatsapp-bridge` still raises `Pocketrb::MissingDependencyError`
- Fix: The agent loop sends a message's media to the provider instead of raising `NoMethodError` (`image?` on a Hash), sends the current message once instead of twice, and keeps the text of earlier media messages after a session is reloaded from storage
- Fix: `pocketrb start --provider` help lists all providers instead of only `anthropic` and `openrouter`

## [0.3.0] - 2026-11-10

### Changed

- Enhancement: Add `openai_compatible` provider for any OpenAI chat completions server (vLLM, llama.cpp, llamafile, LM Studio, Ollama), configured with `openai_compatible_base_url` and an optional `openai_compatible_api_key`
- Enhancement: Add Ruby warning category opt-in to test helpers
- Maintenance: Add `fugit` as a runtime dependency, so cron expressions work without installing it separately
- Maintenance: Require Ruby 4.0+ (`required_ruby_version` was `>= 3.2.0`; Ruby 3.2 is EOL and CI tests only Ruby 4.0)
- Maintenance: Document `@return [Boolean]` on predicate methods to satisfy yard-lint 1.13.0
- Maintenance: Remove unused runtime dependencies `anthropic`, `pastel`, `tty-markdown` and `tty-prompt`, allow `json` 3.x (`web_fetch` converts a body without a charset to UTF-8, and tool-call arguments with a duplicate key keep the last value, as on json 2.x) and drop the duplicate `playwright-ruby-client` entry from the `Gemfile`
- Maintenance: Remove the leftover `README_ANALYSIS.md`, the placeholder WhatsApp bridge link from the README and list all providers under `chat --provider`

### Fixed

- Fix: `pocketrb whatsapp` without the `websocket-client-simple` gem raises `Pocketrb::MissingDependencyError` (a `LoadError`) that says to add the gem, instead of a bare `LoadError` (#14)
- Fix: Cron jobs with a cron expression run on that schedule instead of every minute when `fugit` was not installed
- Fix: `web_fetch` replaces invalid bytes in the response body, so such a page no longer fails with `invalid byte sequence` (declared charset) or raises `JSON::GeneratorError` in the next provider request (no charset)
- Fix: `Providers::OpenRouter#chat_stream` no longer raises `FrozenError` on the first streamed chunk
- Fix: `InboundMessage#has_media?` returns `false` instead of `nil` when media is `nil`
- Fix: Replace retired default models with `claude-sonnet-5-5` (Anthropic, config) and `anthropic/claude-sonnet-5.5` (OpenRouter)
- Fix: `Providers::Anthropic` does not send `temperature` to models that reject it (Opus 4.7+, Sonnet 5+, Haiku 5+, Fable and Mythos, dated IDs included)
- Fix: `Providers::Anthropic::MODELS` lists `claude-opus-5-5`, `claude-sonnet-5-5` and `claude-haiku-5-5` with their 1M context window, so compaction no longer triggers at 200K
- Fix: `Providers::RubyLLMProvider` no longer crashes on every call: rewritten on `ruby_llm` 2.x (dependency now `~> 2.0`), sends the whole history (assistant and tool messages included) in one request per turn, passes tool definitions, returns tool calls to the agent loop and streams through `chat_stream`
- Fix: `ClaudeCLI` model aliases report current model IDs; OpenRouter popular models drop IDs OpenRouter no longer serves

## [0.2.0] - 2026-03-30

### Added

- Rolling summaries in context compaction — prior summary is preserved and incorporated into new summaries across compaction cycles, preventing progressive context loss
- Pressure-based compaction thresholds — compaction triggers when estimated tokens exceed a configurable percentage of the model's context window (`context_pressure`, default 70%)
- Background (non-blocking) compaction via `schedule_compaction` with mutex-based thread safety and `wait_for_compaction` for clean shutdown
- Compaction callbacks (`on_compact`) — fires after successful compaction with summary text and compacted message count
- Separate compaction model configuration (`compaction_model` config key, `POCKETRB_COMPACTION_MODEL` env var) to use a cheaper/faster model for summaries
- `context_pressure` configuration (`compaction_pressure` config key, `POCKETRB_COMPACTION_PRESSURE` env var)
- `Providers::Base#context_window` method (default 200K); `Providers::Anthropic` overrides using MODELS hash

## [0.1.0] - 2026-02-04

### Added

- Initial release
- Core infrastructure with MessageBus for async message passing
- Multi-LLM provider support (Anthropic API, Anthropic OAuth/Max, OpenRouter, RubyLLM, ClaudeCLI)
- Agent loop with tool execution and iteration handling
- Session management with JSONL persistence
- Context compaction for long conversations (40 messages / 50K tokens threshold)
- Core tools: read_file, write_file, edit_file, list_dir, exec, web_search, web_fetch, think, plan
- Simple JSON-based memory system with keyword matching (no external dependencies)
- Memory tool for storing/recalling facts, preferences, and context
- Multi-channel support: CLI, Telegram, WhatsApp (via bridge)
- Skills system with SKILL.md files and runtime creation
- Built-in skills: proactive, reflection
- Planning system for complex multi-step tasks
- Cron service for scheduled tasks
- Job queue for long-running background commands
- Vision support for image analysis (Claude providers)
- Browser automation tools (Playwright integration)
- File sending capabilities (Telegram)
- CLI commands: chat, telegram, whatsapp, gateway, config, skills, cron, jobs
- Configuration management with workspace and global configs
- Persona support (separate memory from workspace)
