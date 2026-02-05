# Pocketrb

[![Gem Version](https://badge.fury.io/rb/pocketrb.svg)](https://badge.fury.io/rb/pocketrb)
[![CI](https://github.com/mensfeld/pocketrb/actions/workflows/ci.yml/badge.svg)](https://github.com/mensfeld/pocketrb/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.txt)

A pocket-sized Ruby AI agent framework with multi-LLM support and advanced capabilities.

## Features

- **Clean async architecture**: MessageBus, proper tool_use API, async processing
- **Multi-LLM support**: Claude (API + Max/OAuth + Proxy), OpenRouter, OpenAI-compatible APIs, RubyLLM, Claude CLI
- **Multi-channel**: CLI, Telegram, WhatsApp (via bridge)
- **Advanced features**: Planning system, context compaction, runtime skills system
- **Simple memory**: JSON-based memory with keyword matching (no external dependencies)
- **Media support**: Vision (images) via Claude, document handling
- **Browser automation**: Headless Chromium with session management and advanced interactions
- **Scheduling**: Cron jobs for automated tasks
- **Personas**: Separate memory and identity from workspace for portable agent personalities
- **Autonomous mode**: Skip permission prompts for sandboxed/container environments

## Installation

```bash
gem install pocketrb
```

Or add to your Gemfile:

```ruby
gem 'pocketrb'
```

## Quick Start

```bash
# Set your API key
export ANTHROPIC_API_KEY=your-key

# Initialize a workspace
pocketrb init

# Start chatting
pocketrb chat
```

## Usage

### CLI Chat

```bash
pocketrb chat [options]
```

Options:
- `-m, --model MODEL` - Model to use (default: claude-sonnet-4-20250514)
- `-p, --provider PROVIDER` - LLM provider (anthropic, openrouter, ruby_llm)
- `-w, --workspace DIR` - Workspace directory for file access
- `-M, --memory-dir DIR` - Memory/persona directory (default: same as workspace)
- `-s, --system-prompt TEXT` - Custom system prompt

### Telegram Bot

```bash
export TELEGRAM_BOT_TOKEN=your-bot-token
pocketrb telegram --allowed-users your_username
```

Options:
- `-t, --token TOKEN` - Bot token (or use env var)
- `-u, --allowed-users` - Restrict access to specific usernames/IDs
- `-w, --workspace` - File access directory
- `-M, --memory-dir` - Persona/memory directory
- `--enable-cron` - Enable cron/scheduling service (default: true)
- `--autonomous` - Skip permission prompts for sandboxed environments

### WhatsApp Bot

Requires the [whatsapp-web.js bridge](https://github.com/user/whatsapp-bridge) running.

```bash
pocketrb whatsapp --bridge-url ws://localhost:3001 --allowed-users +1234567890
```

### Separating Workspace from Memory (Personas)

Run with full filesystem access but a specific persona's memory:

```bash
pocketrb telegram \
  --workspace / \
  --memory-dir ~/.pocketrb/personas/koda \
  --token "$TELEGRAM_BOT_TOKEN" \
  --allowed-users your_username
```

This gives the agent:
- Full filesystem access via `--workspace /`
- Koda's personality and memory via `--memory-dir`

## Personas

Personas allow you to give the agent a persistent identity and memory separate from the working directory.

### Directory Structure

```
~/.pocketrb/personas/my-agent/
├── IDENTITY.md      # Agent personality and instructions
├── MEMORY.md        # Background knowledge and facts
├── memory/          # Daily notes
│   ├── 2026-02-01.md
│   └── 2026-02-02.md
├── skills/          # Custom skills
└── .pocketrb/
    ├── config.yml   # Agent-specific config
    └── sessions/    # Conversation history
```

### IDENTITY.md

Defines who the agent is. Loaded into the system prompt automatically.

```markdown
# Agent Identity

## Who I Am

**Name:** Assistant
**Role:** Helpful AI assistant
**Personality:** Friendly, direct, technically skilled

## How I Work

- I verify before claiming things are done
- I explain what I'm doing when executing commands
- I ask for clarification when requirements are unclear

## Communication Style

- Concise and direct
- Technical when appropriate
- No unnecessary pleasantries
```

### MEMORY.md

Background knowledge the agent should always have access to.

```markdown
# Background Knowledge

## User Information

- **Name**: John
- **Timezone**: UTC+1
- **Preferences**: Prefers Python over JavaScript

## Project Context

- Working on a web scraping project
- Database is PostgreSQL 16
- Deployment target is AWS Lambda
```

## Skills

Skills are reusable prompts that extend the agent's capabilities.

### Creating Skills

Create a skill in `skills/skill-name/SKILL.md`:

```markdown
---
name: code-review
description: Review code for quality and best practices
triggers:
  - review
  - code review
  - check this code
metadata:
  emoji: "🔍"
  requires:
    bins: []
---

# Code Review Skill

When reviewing code, analyze:

1. **Correctness**: Does it do what it's supposed to?
2. **Readability**: Is the code clear and well-organized?
3. **Performance**: Any obvious inefficiencies?
4. **Security**: Input validation, injection risks, etc.
5. **Edge cases**: What happens with unexpected input?

Provide specific, actionable feedback with line numbers.
```

### Skill Frontmatter

| Field | Description |
|-------|-------------|
| `name` | Skill identifier |
| `description` | Short description shown in skill list |
| `triggers` | Phrases that activate this skill |
| `always` | If true, always loaded into context |
| `metadata.emoji` | Display emoji |
| `metadata.requires.bins` | Required binaries (e.g., `["git", "docker"]`) |
| `metadata.os` | Supported OS (e.g., `["linux", "darwin"]`) |

### Built-in Skills

Pocketrb includes several built-in skills:

- **github** - GitHub CLI operations (`gh pr`, `gh issue`, etc.)
- **tmux** - Tmux session management for isolated workspaces
- **weather** - Weather forecasts via wttr.in
- **proactive** - Proactive task management and suggestions
- **reflection** - Self-reflection and learning from interactions

### Listing Skills

```bash
pocketrb skills
```

### Runtime Skill Creation

The agent can create new skills at runtime using the `skill_create` tool:

```
Create a skill called "deploy" that guides deployment to production
```

## Tools

### File Operations

| Tool | Description |
|------|-------------|
| `read_file` | Read file contents with line numbers |
| `write_file` | Write content to a file |
| `edit_file` | Search/replace editing |
| `list_dir` | List directory contents |

### Execution

| Tool | Description |
|------|-------------|
| `exec` | Execute shell commands (auto-backgrounds long commands) |
| `jobs` | Manage background jobs and check their status |

### Web & Browser

| Tool | Description |
|------|-------------|
| `web_search` | Search the web (requires `BRAVE_API_KEY`) |
| `web_fetch` | Fetch and extract content from URLs |
| `browser_advanced` | Advanced browser automation with Chromium (screenshots, interactions, JavaScript) |

### Memory & Knowledge

| Tool | Description |
|------|-------------|
| `think` | Internal reasoning for complex problems |
| `memory` | Store and search long-term memory (keyword-based) |

### Communication

| Tool | Description |
|------|-------------|
| `message` | Send messages to channels (Telegram, WhatsApp) |
| `send_file` | Send files (images, documents) to chat channels |

### Scheduling

| Tool | Description |
|------|-------------|
| `cron` | Schedule and manage recurring tasks |

## Providers

### Anthropic (default)

Standard Anthropic API:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
pocketrb chat --provider anthropic
```

### Claude Max (OAuth)

For Claude Max subscribers using OAuth token:

```bash
export ANTHROPIC_OAUTH_TOKEN=your-oauth-token
pocketrb chat --provider anthropic
```

### Claude Max Proxy

Alternative Claude Max access via proxy:

```bash
pocketrb chat --provider claude_max_proxy
```

### Claude CLI

Use the official Claude CLI (requires `claude` binary):

```bash
pocketrb chat --provider claude_cli
```

### OpenRouter

Access multiple models:

```bash
export OPENROUTER_API_KEY=your-key
pocketrb chat --provider openrouter --model anthropic/claude-sonnet-4
```

### RubyLLM

Use Ruby-based LLM implementations:

```bash
pocketrb chat --provider ruby_llm
```

## Memory System

Pocketrb uses a simple, dependency-free memory system:

### Static Memory

- **MEMORY.md** - Static background knowledge loaded into every conversation
- **IDENTITY.md** - Agent personality and instructions

### Dynamic Memory

The agent can store and recall facts using the `memory` tool:

**Categories:**
- `learned` - Things the agent has learned (e.g., "deployment process")
- `user` - User information (e.g., "timezone: UTC+1")
- `preference` - User preferences (e.g., "coding_style: functional")
- `context` - General context (e.g., "database: PostgreSQL 16")

**Storage:**
- Facts stored in `memory/facts.json`
- Recent events in `memory/recent.json`
- Simple keyword matching for relevance (no vector DB required)

**Usage:**
```
Agent: I'll remember that your timezone is UTC+1
[Uses memory tool: store, category: user, key: "timezone", value: "UTC+1"]

User: What's my timezone?
Agent: [Recalls from memory] Your timezone is UTC+1
```

## Scheduling

### Cron Jobs

Schedule recurring tasks:

```bash
# Add a job that runs every hour
pocketrb cron add --name "hourly-check" --message "Check system status" --every 3600

# Add a cron-style job (9am daily)
pocketrb cron add --name "morning-report" --message "Generate daily report" --cron "0 9 * * *"

# Add a one-time job
pocketrb cron add --name "reminder" --message "Meeting in 10 minutes" --at "2026-02-03T14:50:00"

# List jobs
pocketrb cron list

# Remove a job
pocketrb cron remove job_id
```


## Gateway Mode

Run all services together with full configuration:

```bash
pocketrb gateway \
  --telegram-token "$TELEGRAM_BOT_TOKEN" \
  --telegram-users your_username \
  --whatsapp-bridge ws://localhost:3001 \
  --whatsapp-users "+1234567890" \
  --enable-cron \
  --enable-heartbeat \
  --heartbeat-interval 1800 \
  --autonomous
```

Options:
- `-m, --model` - Model to use
- `-p, --provider` - LLM provider
- `--telegram-token` - Telegram bot token
- `--telegram-users` - Allowed Telegram usernames/IDs
- `--whatsapp-bridge` - WhatsApp bridge WebSocket URL (default: ws://localhost:3001)
- `--whatsapp-users` - Allowed WhatsApp phone numbers
- `--enable-cron` - Enable cron service (default: true)
- `--enable-heartbeat` - Enable heartbeat service (default: true)
- `--heartbeat-interval` - Heartbeat interval in seconds (default: 1800)
- `--autonomous` - Skip permission prompts for sandboxed environments

## Context Compaction

Long conversations are automatically summarized to save tokens:

- Triggers after 40 messages or ~50k tokens
- Keeps last 15 messages intact
- Summarizes older messages using the LLM
- Falls back to basic summary if LLM fails

## Configuration

### Config File

Located at `workspace/.pocketrb/config.yml` or `~/.pocketrb/config.yml`:

```yaml
provider: anthropic
model: claude-sonnet-4-20250514
max_iterations: 50
```

### Commands

```bash
pocketrb config show
pocketrb config set model claude-opus-4-20250514
pocketrb config get model
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `ANTHROPIC_API_KEY` | Anthropic API key |
| `ANTHROPIC_OAUTH_TOKEN` | Claude Max OAuth token |
| `OPENROUTER_API_KEY` | OpenRouter API key |
| `BRAVE_API_KEY` | Brave Search API key (for web_search tool) |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token |
| `POCKETRB_PROVIDER` | Default provider (anthropic, openrouter, ruby_llm, claude_cli, claude_max_proxy) |
| `POCKETRB_MODEL` | Default model |
| `POCKETRB_LOG_LEVEL` | Log level (debug, info, warn, error) |
| `POCKETRB_AUTONOMOUS` | Enable autonomous mode (1, true) - skips permission prompts |
| `POCKETRB_MAX_ITERATIONS` | Maximum agent loop iterations |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Pocketrb Core                           │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ MessageBus  │  │ LLMProvider │  │    Memory System        │  │
│  │ (Async::Q)  │  │ (multi-LLM) │  │ (JSON + keyword match)  │  │
│  └──────┬──────┘  └──────┬──────┘  └───────────┬─────────────┘  │
│         │                │                      │                │
│  ┌──────▼──────────────────▼──────────────────────▼─────────┐   │
│  │                    AgentLoop                              │   │
│  │  - Context building (identity, memory, history)           │   │
│  │  - Tool execution via ToolRegistry                        │   │
│  │  - Context compaction for long conversations              │   │
│  │  - Session management (JSONL persistence)                 │   │
│  └──────────────────────────────────────────────────────────┘   │
│         │                │                                       │
│  ┌──────▼──────┐  ┌──────▼──────┐  ┌──────────────────────┐     │
│  │ SkillLoader │  │ CronService │  │    ToolRegistry      │     │
│  │ (SKILL.md)  │  │ (schedule)  │  │ (file, exec, web...) │     │
│  └─────────────┘  └─────────────┘  └──────────────────────┘     │
│         │                                                        │
│  ┌──────▼────────────────────────────────────────────────────┐  │
│  │                      Channels                              │  │
│  │  CLI  │  Telegram  │  WhatsApp  │  (extensible)            │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Development

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Run specific test
bundle exec rspec spec/unit/tools/read_file_spec.rb

# Interactive console
bundle exec irb -r ./lib/pocketrb
```

## License

MIT License - see LICENSE.txt
