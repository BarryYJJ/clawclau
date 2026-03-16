#!/bin/bash
# claude-check.sh — Check status of Claude Code tasks
# Usage: claude-check.sh [task-id]

set -euo pipefail

CLAWCLAU_HOME="${CLAWCLAU_HOME:-$HOME/.openclaw/workspace/.clawdbot}"
TASK_REGISTRY="$CLAWCLAU_HOME/active-tasks.json"

# --- Dependency check ---
command -v tmux >/dev/null 2>&1 || { echo "ERROR: 'tmux' is required but not installed."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: 'jq' is required but not installed."; exit 1; }

if [ ! -f "$TASK_REGISTRY" ]; then
    echo "ERROR: Task registry not found at '$TASK_REGISTRY'. Run claude-spawn.sh first."
    exit 1
fi

if [ $# -gt 0 ]; then
    # Check single task
    TASK_ID="$1"
    TMUX_SESSION="claude-${TASK_ID}"

    # Read status from registry
    STATUS=$(jq -r --arg id "$TASK_ID" '.[] | select(.id == $id) | .status // "unknown"' "$TASK_REGISTRY")

    if [ "$STATUS" = "unknown" ]; then
        echo "ERROR: Task '$TASK_ID' not found in registry"
        exit 1
    fi

    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        STATUS="running"
        LAST_LINES=$(tmux capture-pane -t "$TMUX_SESSION" -p | tail -10)
    fi

    INFO=$(jq -r --arg id "$TASK_ID" '.[] | select(.id == $id)' "$TASK_REGISTRY")

    echo "=== Task: $TASK_ID ==="
    echo "Status: $STATUS"
    if [ -n "$INFO" ]; then
        echo "$INFO" | jq -r '"Prompt: \(.prompt)\nWorkdir: \(.workdir)\nStarted: \(.startedAt)"'
    fi
    if [ "$STATUS" = "running" ]; then
        echo "--- Last output ---"
        echo "$LAST_LINES"
    fi
else
    # List all tasks
    echo "=== Claude Code Tasks ==="

    jq -r '.[] | "- \(.id) [\(.status)] tmux:\(.tmuxSession) started:\(.startedAt)"' "$TASK_REGISTRY" 2>/dev/null || echo "(no tasks)"

    echo ""
    echo "=== Live tmux sessions ==="
    tmux list-sessions 2>/dev/null | grep "^claude-" | while read line; do
        SESSION=$(echo "$line" | cut -d: -f1)
        TASK_ID="${SESSION#claude-}"
        echo "  $SESSION — $(tmux capture-pane -t "$SESSION" -p | tail -3 | tr '\n' ' ')"
    done || echo "  (none)"
fi
