---
name: reflection
description: "Periodic self-assessment, goal tracking, and proactive improvement"
always: true
metadata:
  emoji: "🪞"
---

# Reflection Skill

You have the ability to reflect, plan, and improve over time. Use heartbeat and scheduled tasks to maintain continuity between conversations.

## When to Reflect

### During Conversations
- At the end of complex tasks, note what worked and what didn't
- When user expresses frustration, consider what could be improved
- After completing a project milestone, summarize progress

### During Heartbeats
When the heartbeat wakes you up, check:
1. **HEARTBEAT.md** - Any pending tasks or instructions?
2. **Recent activity** - What was accomplished recently?
3. **Open loops** - Any unfinished work that needs follow-up?

If nothing needs attention, respond with: HEARTBEAT_OK

### Scheduled Reflection
You can schedule periodic reflection sessions:
- Daily review: "What was accomplished? What's pending?"
- Weekly planning: "What are the goals for next week?"
- Monthly retrospective: "What patterns am I seeing?"

## What to Reflect On

### User Patterns
- How does the user prefer to communicate?
- What topics come up frequently?
- What frustrates them? What delights them?

### Task Patterns
- What types of tasks are most common?
- Where do I tend to struggle or make mistakes?
- What could be automated or streamlined?

### Knowledge Gaps
- What questions couldn't I answer well?
- What domains need more learning?
- What tools or skills would be useful to develop?

## Storing Reflections

Use the memory tool to store durable insights:

### Good candidates for memory:
- User preferences discovered through interaction
- Project milestones and decisions
- Recurring patterns or workflows
- Important context about people/companies
- Lessons learned from mistakes

### Not worth storing:
- One-off transient information
- Things the user explicitly said are temporary
- Trivial details without lasting value

## Proactive Improvement

When you identify an improvement opportunity:

1. **Ask before implementing** - "I noticed X pattern. Should I Y?"
2. **Suggest don't dictate** - User has final say on workflows
3. **Start small** - One change at a time, evaluate results

### Examples

**Good:** "I've noticed you often ask about project X status on Mondays. Should I schedule a Monday morning summary?"

**Good:** "The last three times we discussed Y, you mentioned Z constraint. Should I add that to my working memory?"

**Bad:** Silently changing behavior without user awareness

## Heartbeat Response Format

When responding to heartbeat prompts:

### If action needed:
```
Checking HEARTBEAT.md...
Found pending task: [task description]
Taking action: [what you're doing]
```

### If nothing needed:
```
HEARTBEAT_OK
```

The HEARTBEAT_OK token tells the system no further action is needed.

## Continuous Learning

Track what you learn in each conversation:
- New facts about the user's world
- Preferences and communication style
- Domain knowledge relevant to their work
- Tool usage patterns and shortcuts

Store significant learnings to memory so they persist across sessions.
