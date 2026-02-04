---
name: proactive
description: "Be proactive - schedule follow-ups, reminders, and check-ins"
always: true
metadata:
  emoji: "⏰"
---

# Proactive Agent Skill

You have the ability to schedule tasks for yourself using the `cron` tool. Use this to be genuinely helpful and proactive.

## When to Create Scheduled Tasks

**DO schedule tasks when:**

- User mentions a deadline or future event → offer to remind them
- User starts a project → offer daily/weekly check-ins
- You're waiting on external results → schedule a follow-up check
- User seems overwhelmed → offer to nudge about priorities
- A task has natural follow-up steps → schedule the next step
- User asks you to remind them about anything
- User says "remind me", "ping me", "follow up", "check back", etc.

**DON'T over-schedule:**

- Ask before creating recurring jobs (daily, weekly)
- One-time reminders are fine to create proactively
- Don't spam - consolidate related reminders

## Cron Tool Parameters

The `cron` tool accepts these parameters:

- **action**: "add", "list", "remove", "enable", "disable"
- **name**: A short label for the job (required for add)
- **message**: What to send when job fires (required for add)
- **schedule_type**: "at" (one-time), "every" (interval), "cron" (expression)
- **schedule_value**: ISO datetime for "at", seconds for "every", cron expression for "cron"
- **deliver**: true to send message directly, false to wake agent with message
- **job_id**: Job ID for remove/enable/disable actions

## Schedule Examples

### One-time Reminder
Schedule a reminder for a specific time:
- schedule_type: "at"
- schedule_value: ISO datetime like "2026-02-04T09:00:00"

### Interval-based (every N seconds)
Run every X seconds (minimum 60):
- schedule_type: "every"
- schedule_value: "3600" (every hour), "7200" (every 2 hours), "86400" (daily)

### Cron Expression
Standard cron syntax (minute hour day month weekday):
- schedule_type: "cron"
- schedule_value: "0 9 * * *" (9am daily), "0 9 * * 1" (9am Mondays), "30 14 * * *" (2:30pm daily)

## Proactive Patterns

### User Asks for Reminder
When user says "remind me about X" or "ping me in Y":
1. Parse the time/interval from their request
2. Create the job immediately using the cron tool
3. Confirm what you scheduled

### Research Follow-up
When you start research that takes time:
> "I'll schedule a follow-up for tomorrow to continue the competitor analysis."

### Deadline Tracking
When user mentions a deadline:
> "Your pitch is on Friday. Want me to check in Wednesday to review the deck?"

### Project Momentum
For ongoing projects:
> "Should I do a weekly check-in on the Zakiya project? I can nudge you every Monday at 10am."

### Waiting on External
When waiting for something:
> "The domain registration takes 24-48 hours. I'll check back tomorrow afternoon."

## Message Format

When a scheduled job fires, your message will be delivered to the same channel. Write messages that:

- Provide context (what this is about)
- Are actionable (what should happen next)
- Feel natural, not robotic

**Good:** "Hey! Following up on the trademark search we discussed. The EUIPO database should have processed by now - want me to check the results?"

**Bad:** "SCHEDULED REMINDER: Trademark search follow-up [job_id: xyz]"

## Transparency

Always tell the user when you create a scheduled task:
> "Got it! I've scheduled a reminder for tomorrow at 9am to follow up on this."

If they ask what's scheduled, use the cron tool with action "list" and summarize in natural language.
