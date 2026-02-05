# README Analysis - Alignment with Codebase

## ✅ Correct Documentation

### Commands
- ✅ `pocketrb init` - Verified
- ✅ `pocketrb chat` with options (-m, -p, -w, -M, -s) - Verified
- ✅ `pocketrb telegram` with options - Verified
- ✅ `pocketrb whatsapp` - Verified
- ✅ `pocketrb gateway` - Verified
- ✅ `pocketrb skills` - Verified
- ✅ `pocketrb plans` - Verified
- ✅ `pocketrb config` subcommands - Verified
- ✅ `pocketrb cron` subcommands - Verified

### Providers
- ✅ `anthropic` - Verified in registry
- ✅ `openrouter` - Verified in registry
- ✅ `ruby_llm` - Verified in registry
- ✅ `claude_cli` - Verified in registry

### Core Tools (Registered by Default)
- ✅ `read_file` (ReadFile) - Verified
- ✅ `write_file` (WriteFile) - Verified
- ✅ `edit_file` (EditFile) - Verified
- ✅ `list_dir` (ListDir) - Verified
- ✅ `exec` (Exec) - Verified
- ✅ `web_search` (WebSearch) - Verified
- ✅ `web_fetch` (WebFetch) - Verified
- ✅ `think` (Think) - Verified
- ✅ `message` (Message) - Verified
- ✅ `send_file` (SendFile) - Verified (but not in README tables)
- ✅ `memory` (Memory) - Verified
- ✅ `jobs` (Jobs) - Verified
- ✅ `cron` (Cron) - Verified
- ✅ `browser_advanced` (BrowserAdvanced) - Verified

### Built-in Skills
- ✅ `github` - Verified in lib/pocketrb/skills/builtin/
- ✅ `tmux` - Verified in lib/pocketrb/skills/builtin/
- ✅ `weather` - Verified in lib/pocketrb/skills/builtin/

### Environment Variables
- ✅ `ANTHROPIC_API_KEY` - Verified
- ✅ `ANTHROPIC_OAUTH_TOKEN` - Verified
- ✅ `OPENROUTER_API_KEY` - Verified
- ✅ `BRAVE_API_KEY` - Verified
- ✅ `TELEGRAM_BOT_TOKEN` - Verified
- ✅ `POCKETRB_PROVIDER` - Verified in config.rb
- ✅ `POCKETRB_MODEL` - Verified in config.rb
- ✅ `POCKETRB_LOG_LEVEL` - Verified in config.rb

### Features
- ✅ MessageBus architecture - Verified
- ✅ Planning system - Verified (lib/pocketrb/planning/)
- ✅ Context compaction - Mentioned correctly
- ✅ Skills system - Verified
- ✅ Memory system - Verified
- ✅ Personas concept - Correctly documented
- ✅ Scheduling/Cron - Verified

---

## ❌ Missing or Incorrect Documentation

### 1. **New Provider Not Documented**
**Issue:** `claude_max_proxy` provider exists but is not mentioned in README.

**Location in code:** `lib/pocketrb/providers/claude_max_proxy.rb`

**Registered as:** `:claude_max_proxy` in registry

**Suggestion:** Add a section documenting the Claude Max Proxy provider.

---

### 2. **New Advanced Tools Not Documented**
**Issue:** Recently added tools are not mentioned in README:

- `browser_advanced` (BrowserAdvanced) - Registered by default
- `browser_session` (BrowserSession) - Exists but not registered by default
- `para_memory` (ParaMemory) - Exists but not registered by default

**Location:**
- `lib/pocketrb/tools/browser_advanced.rb`
- `lib/pocketrb/tools/browser_session.rb`
- `lib/pocketrb/tools/para_memory.rb`

**Suggestion:** Add these to the tools table with descriptions.

---

### 3. **New Built-in Skills Not Documented**
**Issue:** Two new built-in skills exist but are not mentioned:

- `proactive` - lib/pocketrb/skills/builtin/proactive/
- `reflection` - lib/pocketrb/skills/builtin/reflection/

**Suggestion:** Add these to the "Built-in Skills" section.

---

### 4. **`spawn` Tool Documentation Issue**
**Issue:** README mentions "spawn" tool for background subagents, but:
- Tool exists at `lib/pocketrb/agent/spawn_tool.rb` (not in tools/)
- Not registered in default tools registry
- Only available when `subagent_manager` is present in context

**Current README says:**
```
| `spawn` | Spawn background subagents for parallel work |
```

**Reality:** Spawn tool exists but is NOT in the default registry, and requires special context setup.

**Suggestion:** Either document that it's conditionally available, or remove it from the default tools table.

---

### 5. **`plan` Tool Not in Registry**
**Issue:** README mentions planning tool:
```
| `plan` | Create and manage multi-step execution plans |
```

**Reality:**
- Planning system exists (lib/pocketrb/planning/)
- No "plan" tool in default registry (lib/pocketrb/tools/registry.rb)
- Planning appears to be a system feature, not a tool

**Suggestion:** Clarify how planning works or remove from tools table.

---

### 6. **`send_file` Tool Missing from Table**
**Issue:** `SendFile` tool is registered by default but not listed in the tools table.

**Location:** `lib/pocketrb/tools/send_file.rb`

**Current:** Only mentioned in "Communication" section description, not as a separate row.

**Suggestion:** Add explicit row in tools table.

---

### 7. **`--autonomous` Flag Not Documented**
**Issue:** Both `telegram` and `gateway` commands support `--autonomous` flag, but README doesn't mention it.

**Code location:**
```ruby
option :autonomous, type: :boolean, default: false,
       desc: "Skip permission prompts (for sandboxed environments)"
```

**Also supports:** `POCKETRB_AUTONOMOUS` environment variable

**Suggestion:** Add to command options and environment variables sections.

---

### 8. **Missing Environment Variable**
**Issue:** `POCKETRB_AUTONOMOUS` env var exists but not documented.

**Location:** Used in `lib/pocketrb/providers/claude_cli.rb` and `lib/pocketrb/config.rb`

**Suggestion:** Add to environment variables table.

---

### 9. **Gateway Command Options Incomplete**
**Issue:** README shows simplified gateway example:
```bash
pocketrb gateway \
  --telegram-token "$TELEGRAM_BOT_TOKEN" \
  --telegram-users your_username \
  --enable-cron
```

**Missing options:**
- `--autonomous` - Skip permission prompts
- `--heartbeat-interval` - Heartbeat interval in seconds
- `--enable-heartbeat` - Enable heartbeat service
- `--whatsapp-bridge` - WhatsApp bridge URL
- `--whatsapp-users` - Allowed WhatsApp numbers

**Suggestion:** Document all gateway options.

---

### 10. **Telegram Command Options Incomplete**
**Issue:** README doesn't mention `--autonomous` and `--enable-cron` flags.

**Actual options:**
```ruby
option :enable_cron, type: :boolean, default: true
option :autonomous, type: :boolean, default: false
```

**Suggestion:** Add these to the Telegram Bot section.

---

### 11. **`jobs` Tool Not in Documentation**
**Issue:** `jobs` tool (Jobs class) is registered by default but not mentioned in README.

**Location:** `lib/pocketrb/tools/jobs.rb`

**Suggestion:** Add to tools table.

---

### 12. **Provider List Incomplete**
**Issue:** README lists 3 providers (anthropic, openrouter, ruby_llm) but codebase has 5:
- anthropic
- openrouter
- ruby_llm
- claude_cli
- claude_max_proxy ← NEW

**Suggestion:** Document all 5 providers.

---

## 📊 Summary Statistics

**Documented Correctly:** ~85%
- Commands: 9/9 ✅
- Core features: All major features ✅
- Basic tools: 10/13 ✅
- Basic providers: 3/5 ⚠️

**Missing Documentation:**
- 2 new tools (browser_session, para_memory)
- 1 tool registered but not documented (jobs)
- 2 new built-in skills (proactive, reflection)
- 1 new provider (claude_max_proxy)
- 2 command flags (--autonomous for telegram/gateway)
- 1 environment variable (POCKETRB_AUTONOMOUS)

**Potentially Incorrect:**
- spawn tool (exists but not in default registry)
- plan tool (planning system exists but no tool with that name)

---

## 🔧 Recommended Actions

### High Priority
1. Add documentation for `claude_max_proxy` provider
2. Document `--autonomous` flag for telegram and gateway
3. Add `POCKETRB_AUTONOMOUS` to environment variables
4. Clarify spawn tool availability (conditional)
5. Fix plan tool documentation (system vs tool)

### Medium Priority
6. Document new browser tools (browser_advanced, browser_session)
7. Document para_memory tool
8. Add jobs tool to documentation
9. Add new skills (proactive, reflection) to built-in skills list
10. Complete gateway command options

### Low Priority
11. Ensure send_file has its own row in tools table
12. Add comprehensive gateway options example

---

## ✨ Positive Notes

The README is **mostly accurate** and well-structured:
- Clear installation and quickstart
- Good examples for all major features
- Personas concept well explained
- Skills system thoroughly documented
- Architecture diagram is helpful
- Code examples are accurate

**Overall Assessment:** The README is in good shape but needs updates for recent additions (new tools, providers, and command flags added in recent commits).
