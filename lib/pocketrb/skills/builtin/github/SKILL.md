---
name: github
description: "Interact with GitHub using the `gh` CLI"
always: false
triggers:
  - github
  - gh
  - pull request
  - pr
  - issue
  - repo
  - workflow
  - actions
requires:
  - bin:gh
metadata:
  pocketrb:
    emoji: "🐙"
---

# GitHub Skill

Use the `gh` CLI for GitHub operations. This skill provides guidance on common GitHub workflows.

## Prerequisites

The `gh` CLI must be installed and authenticated:
```bash
# Install (macOS)
brew install gh

# Install (Linux)
# See https://github.com/cli/cli/blob/trunk/docs/install_linux.md

# Authenticate
gh auth login
```

## Common Commands

### Pull Requests

```bash
# List PRs
gh pr list --repo owner/repo

# View PR details
gh pr view 55 --repo owner/repo

# Check PR status/checks
gh pr checks 55 --repo owner/repo

# Create PR
gh pr create --title "Title" --body "Description"

# Merge PR
gh pr merge 55 --squash --delete-branch

# Review PR
gh pr diff 55 --repo owner/repo
```

### Issues

```bash
# List issues
gh issue list --repo owner/repo

# View issue
gh issue view 123 --repo owner/repo

# Create issue
gh issue create --title "Bug" --body "Description"

# Close issue
gh issue close 123
```

### Workflows / Actions

```bash
# List workflow runs
gh run list --repo owner/repo --limit 10

# View run details
gh run view 12345 --repo owner/repo

# Watch a run
gh run watch 12345 --repo owner/repo

# Rerun failed jobs
gh run rerun 12345 --failed
```

### API Access

```bash
# Get PR info as JSON
gh api repos/owner/repo/pulls/55 --jq '.title'

# Get issue comments
gh api repos/owner/repo/issues/123/comments

# Create a comment
gh api repos/owner/repo/issues/123/comments -f body="Comment text"
```

## Tips

- Use `--repo owner/repo` or `-R owner/repo` to specify repository
- Use `--json field1,field2` to get specific fields as JSON
- Use `--jq '.field'` to filter JSON output
- Most commands support `--web` to open in browser
