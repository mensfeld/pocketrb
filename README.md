# Pocketrb

A pocket-sized Ruby AI agent framework with multi-LLM support and advanced capabilities.

## Features

- **Clean async architecture**: MessageBus, proper tool_use API, async processing, subagent spawning
- **Multi-LLM support**: Claude (API + Max/OAuth), OpenRouter, OpenAI-compatible APIs
- **Multi-channel**: CLI, Telegram, WhatsApp (via bridge)
- **Advanced features**: Planning system, context compaction, runtime skills, QMD memory via MCP
- **Media support**: Vision (images) via Claude, document handling
- **Scheduling**: Cron jobs, heartbeat service for periodic wake-ups
- **Personas**: Separate memory and identity from workspace for portable agent personalities

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
- `-p, --provider PROVIDER` - LLM provider (anthropic, openrouter)
- `-w, --workspace DIR` - Workspace directory for file access
- `-M, --memory-dir DIR` - Memory/persona directory (default: same as workspace)
- `--no-qmd` - Disable QMD memory integration

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
| `spawn` | Spawn background subagents for parallel work |

### Web

| Tool | Description |
|------|-------------|
| `web_search` | Search the web (requires `BRAVE_API_KEY`) |
| `web_fetch` | Fetch and extract content from URLs |

### Planning & Memory

| Tool | Description |
|------|-------------|
| `think` | Internal reasoning for complex problems |
| `plan` | Create and manage multi-step execution plans |
| `memory` | Store and search long-term memory |

### Communication

| Tool | Description |
|------|-------------|
| `message` | Send messages to channels (Telegram, WhatsApp) |

## Providers

### Anthropic (default)

```bash
export ANTHROPIC_API_KEY=sk-ant-...
pocketrb chat --provider anthropic
```

### Claude Max (OAuth)

For Claude Max subscribers:

```bash
export ANTHROPIC_OAUTH_TOKEN=your-oauth-token
pocketrb chat --provider anthropic
```

### OpenRouter

Access multiple models:

```bash
export OPENROUTER_API_KEY=your-key
pocketrb chat --provider openrouter --model anthropic/claude-sonnet-4
```

## Memory System

Pocketrb has a multi-layer memory system:

### Local Memory

- **MEMORY.md** - Static background knowledge
- **Daily notes** - `memory/YYYY-MM-DD.md` files for daily learnings

### QMD Integration (Optional)

Connect to [QMD](https://github.com/user/qmd) for vector-based semantic search:

```bash
export MCP_ENDPOINT=http://localhost:7878
pocketrb chat  # QMD enabled by default
```

Disable with `--no-qmd`.

### Memory Commands

```bash
# Check QMD status
pocketrb qmd status

# Search memory
pocketrb qmd search "deployment process"

# Store to memory
pocketrb qmd store "PostgreSQL runs on port 5432" --topic infrastructure

# Sync local to QMD
pocketrb qmd sync
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

### Heartbeat Service

Periodic wake-up to check for pending tasks. Create `HEARTBEAT.md` in your workspace:

```markdown
# Pending Tasks

- [ ] Check if backup completed
- [ ] Review overnight logs
```

The agent will periodically read this file and act on it.

## Gateway Mode

Run all services together:

```bash
pocketrb gateway \
  --telegram-token "$TELEGRAM_BOT_TOKEN" \
  --telegram-users your_username \
  --enable-cron \
  --enable-heartbeat \
  --heartbeat-interval 1800
```

## Context Compaction

Long conversations are automatically summarized to save tokens:

- Triggers after 30 messages or ~50k tokens
- Keeps last 10 messages intact
- Summarizes older messages using the LLM
- Falls back to basic summary if LLM fails

## Configuration

### Config File

Located at `workspace/.pocketrb/config.yml`:

```yaml
provider: anthropic
model: claude-sonnet-4-20250514
max_iterations: 50
mcp_endpoint: http://localhost:7878
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
| `BRAVE_API_KEY` | Brave Search API key |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token |
| `MCP_ENDPOINT` | QMD/MCP server endpoint |
| `POCKETRB_PROVIDER` | Default provider |
| `POCKETRB_MODEL` | Default model |
| `POCKETRB_LOG_LEVEL` | Log level (debug, info, warn, error) |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Pocketrb Core                           │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ MessageBus  │  │ LLMProvider │  │    MCP Client           │  │
│  │ (Async::Q)  │  │ (multi-LLM) │  │ (QMD Memory Bridge)     │  │
│  └──────┬──────┘  └──────┬──────┘  └───────────┬─────────────┘  │
│         │                │                      │                │
│  ┌──────▼──────────────────▼──────────────────────▼─────────┐   │
│  │                    AgentLoop                              │   │
│  │  - Context building (identity, memory, history)           │   │
│  │  - Tool execution via ToolRegistry                        │   │
│  │  - Context compaction for long conversations              │   │
│  │  - Planning system                                        │   │
│  └──────────────────────────────────────────────────────────┘   │
│         │                │                      │                │
│  ┌──────▼──────┐  ┌──────▼──────┐  ┌───────────▼─────────────┐  │
│  │ SessionMgr  │  │ SkillLoader │  │    SubagentManager      │  │
│  │ (JSONL)     │  │ (SKILL.md)  │  │    (spawn/coordinate)   │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
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
