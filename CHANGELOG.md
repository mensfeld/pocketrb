# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
