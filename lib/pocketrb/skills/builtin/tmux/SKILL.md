---
name: tmux
description: "Remote-control tmux sessions for interactive CLIs"
always: false
triggers:
  - tmux
  - terminal
  - session
  - multiplexer
requires:
  - bin:tmux
metadata:
  pocketrb:
    emoji: "🧵"
    os:
      - darwin
      - linux
---

# Tmux Skill

Control tmux sessions via socket for isolated agent workspaces. This allows running and interacting with persistent terminal sessions.

## Socket Setup

Use a dedicated socket directory to avoid conflicts:

```bash
SOCKET_DIR="${POCKETRB_TMUX_SOCKET_DIR:-${TMPDIR:-/tmp}/pocketrb-tmux-sockets}"
mkdir -p "$SOCKET_DIR"
SOCKET="$SOCKET_DIR/pocketrb.sock"
```

## Basic Commands

### Session Management

```bash
# Create a new session
tmux -S "$SOCKET" new-session -d -s mysession

# Create session with initial command
tmux -S "$SOCKET" new-session -d -s mysession "irb"

# List sessions
tmux -S "$SOCKET" list-sessions

# Kill a session
tmux -S "$SOCKET" kill-session -t mysession

# Attach to session (interactive)
tmux -S "$SOCKET" attach -t mysession
```

### Sending Commands

```bash
# Send keys (commands) to a session
tmux -S "$SOCKET" send-keys -t mysession "ls -la" Enter

# Send literal text (no Enter)
tmux -S "$SOCKET" send-keys -t mysession -l "some text"

# Send special keys
tmux -S "$SOCKET" send-keys -t mysession C-c  # Ctrl+C
tmux -S "$SOCKET" send-keys -t mysession C-d  # Ctrl+D
tmux -S "$SOCKET" send-keys -t mysession Up   # Arrow up
```

### Capturing Output

```bash
# Capture visible pane content
tmux -S "$SOCKET" capture-pane -p -t mysession

# Capture with history (last 200 lines)
tmux -S "$SOCKET" capture-pane -p -J -t mysession -S -200

# Capture to file
tmux -S "$SOCKET" capture-pane -p -t mysession > output.txt
```

## Common Patterns

### Run Command and Get Output

```bash
# Send command
tmux -S "$SOCKET" send-keys -t mysession "ruby script.rb" Enter

# Wait for completion (simple approach)
sleep 2

# Capture output
tmux -S "$SOCKET" capture-pane -p -J -t mysession -S -50
```

### Interactive Ruby/IRB Session

```bash
# Start IRB session
tmux -S "$SOCKET" new-session -d -s ruby "irb"

# Send Ruby commands
tmux -S "$SOCKET" send-keys -t ruby "require 'pathname'" Enter
tmux -S "$SOCKET" send-keys -t ruby "puts Pathname.pwd" Enter

# Get output
sleep 1
tmux -S "$SOCKET" capture-pane -p -t ruby
```

### SSH Session

```bash
# Start SSH session
tmux -S "$SOCKET" new-session -d -s remote "ssh user@host"

# Wait for connection, then send commands
sleep 3
tmux -S "$SOCKET" send-keys -t remote "ls -la" Enter
```

## Tips

- Use `-l` flag with `send-keys` for literal text to avoid interpretation
- The `-J` flag in `capture-pane` joins wrapped lines
- Use `-S -N` in `capture-pane` to capture last N lines of history
- Clean up sessions when done to avoid resource leaks
- Use unique session names to avoid conflicts
