# Pocketrb

A pocket-sized Ruby AI agent framework with multi-LLM support and advanced capabilities.

## Features

- **Clean async architecture**: MessageBus, proper tool_use API, async processing, subagent spawning
- **Multi-LLM support**: Claude (API + Max/OAuth), OpenRouter, OpenAI-compatible APIs
- **Multi-channel**: CLI, Telegram, WhatsApp (via bridge)
- **Advanced features**: Planning system, context compaction, runtime skills, QMD memory via MCP
- **Media support**: Vision (images) via Claude, document handling
- **Scheduling**: Cron jobs, heartbeat service for periodic wake-ups

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'pocketrb'
```

Or install directly:

```bash
gem install pocketrb
```

## Quick Start

1. Set your API key:
```bash
export ANTHROPIC_API_KEY=your-key
```

2. Initialize a workspace:
```bash
pocketrb init
```

3. Start chatting:
```bash
pocketrb chat
```

## Usage

### Interactive Chat

```bash
pocketrb chat
```

Options:
- `-m, --model MODEL` - Model to use (default: claude-sonnet-4-20250514)
- `-p, --provider PROVIDER` - LLM provider (anthropic, openrouter)
- `-w, --workspace DIR` - Workspace directory

### Continuous Mode

```bash
pocketrb start
```

### Configuration

```bash
# Show config
pocketrb config show

# Set a value
pocketrb config set model claude-opus-4-20250514

# Get a value
pocketrb config get model
```

### Skills

Skills are reusable prompts that can be loaded into the agent's context:

```bash
# List available skills
pocketrb skills
```

Create skills in `workspace/skills/skill-name/SKILL.md`:

```markdown
---
name: code-review
description: Review code for quality and best practices
triggers:
  - review
  - code review
---

When reviewing code, focus on:
1. Code clarity and readability
2. Potential bugs or edge cases
3. Performance implications
4. Security considerations
```

### Plans

Track complex multi-step tasks:

```bash
# List active plans
pocketrb plans
```

The agent can create and manage plans via the `plan` tool.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Pocketrb Core                              │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ MessageBus  │  │ LLMProvider │  │    MCP Client           │  │
│  │ (Async::Q)  │  │ (multi-LLM) │  │ (QMD Memory Bridge)     │  │
│  └──────┬──────┘  └──────┬──────┘  └───────────┬─────────────┘  │
│         │                │                      │                │
│  ┌──────▼──────────────────▼──────────────────────▼─────────┐   │
│  │                    AgentLoop                              │   │
│  │  - Context building (system prompt, history, memory)      │   │
│  │  - Tool execution via ToolRegistry                        │   │
│  │  - Planning system                                        │   │
│  │  - Self-modification support                              │   │
│  └──────────────────────────────────────────────────────────┘   │
│         │                │                      │                │
│  ┌──────▼──────┐  ┌──────▼──────┐  ┌───────────▼─────────────┐  │
│  │ SessionMgr  │  │ SkillLoader │  │    SubagentManager      │  │
│  │ (JSONL)     │  │ (SKILL.md)  │  │    (spawn/coordinate)   │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Providers

### Anthropic (default)

Direct Claude API access with full feature support including extended thinking.

```bash
export ANTHROPIC_API_KEY=your-key
pocketrb chat --provider anthropic
```

### OpenRouter

Access multiple models through OpenRouter:

```bash
export OPENROUTER_API_KEY=your-key
pocketrb chat --provider openrouter --model anthropic/claude-sonnet-4
```

## Built-in Tools

- `read_file` - Read file contents
- `write_file` - Write content to files
- `edit_file` - Edit files with search/replace
- `list_dir` - List directory contents
- `exec` - Execute shell commands
- `web_search` - Search the web (requires Brave API key)
- `web_fetch` - Fetch web page content
- `think` - Internal reasoning tool
- `plan` - Create and manage execution plans
- `memory` - Long-term memory via MCP/QMD
- `skill_create` - Create new skills at runtime
- `skill_modify` - Modify existing skills
- `spawn` - Spawn subagents for parallel work

## Environment Variables

- `ANTHROPIC_API_KEY` - Anthropic API key
- `OPENROUTER_API_KEY` - OpenRouter API key
- `BRAVE_API_KEY` - Brave Search API key
- `MCP_ENDPOINT` - MCP server endpoint (default: http://localhost:7878)
- `POCKETRB_PROVIDER` - Default provider
- `POCKETRB_MODEL` - Default model
- `POCKETRB_LOG_LEVEL` - Log level (debug, info, warn, error)

## Development

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rake spec

# Run linter
bundle exec rake rubocop

# Generate documentation
bundle exec rake docs
```

## License

MIT License - see LICENSE.txt
