# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-02-03

### Added

- Initial release
- Core infrastructure with MessageBus for async message passing
- Multi-LLM provider support (Anthropic, OpenRouter, RubyLLM)
- Agent loop with tool execution and iteration handling
- Session management with JSONL persistence
- Core tools: read_file, write_file, edit_file, list_dir, exec, web_search, web_fetch, think
- MCP client for QMD memory integration
- Skills system with SKILL.md files and runtime creation
- Planning system for complex multi-step tasks
- Subagent spawning for parallel task execution
- CLI with chat, run, config, and skills commands
- Configuration management with workspace and global configs
