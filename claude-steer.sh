#!/bin/bash
# claude-steer.sh — Send a message to a running Claude Code session (mid-task correction)
# Usage: claude-steer.sh <task-id> "<message>"

set -euo pipefail

CLAWCLAU_HOME="${CLAWCLAU_HOME:-$HOME/.openclaw/workspace/.clawdbot}"

# --- Argument validation ---
if [ $# -lt 2 ]; then
    echo "Usage: claude-steer.sh <task-id> \"<message>\""
    exit 1
fi

TASK_ID="$1"
MESSAGE="$2"
TMUX_SESSION="claude-${TASK_ID}"

# --- Dependency check ---
command -v tmux >/dev/null 2>&1 || { echo "ERROR: 'tmux' is required but not installed."; exit 1; }

if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "ERROR: tmux session '$TMUX_SESSION' not found"
    exit 1
fi

# Send message to the running session
tmux send-keys -t "$TMUX_SESSION" "$MESSAGE" Enter

echo "OK: sent message to '$TMUX_SESSION'"
