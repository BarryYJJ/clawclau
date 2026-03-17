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

    LAST_LINES=""
    LOG_PREVIEW=""
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        STATUS="running"
        LAST_LINES=$(tmux capture-pane -t "$TMUX_SESSION" -p 2>/dev/null | tail -10 || true)
    else
        # Session done — show last lines from log file (strip ANSI)
        LOG_FILE=$(jq -r --arg id "$TASK_ID" '.[] | select(.id == $id) | .log // ""' "$TASK_REGISTRY")
        if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
            LOG_PREVIEW=$(sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x0f//g; s/\x07//g' "$LOG_FILE" | strings | grep -v '^\[' | grep -v '^]' | grep -v '^$' | tail -10 || true)
        fi
    fi

    INFO=$(jq -r --arg id "$TASK_ID" '.[] | select(.id == $id)' "$TASK_REGISTRY")

    echo "=== Task: $TASK_ID ==="
    echo "Status: $STATUS"
    if [ -n "$INFO" ]; then
        echo "$INFO" | jq -r '"Prompt: \(.prompt)\nWorkdir: \(.workdir)\nStarted: \(.startedAt)"'
    fi
    if [ "$STATUS" = "running" ]; then
        echo "--- Last output (tmux) ---"
        echo "$LAST_LINES"
    elif [ -n "$LOG_PREVIEW" ]; then
        echo "--- Last output (log) ---"
        echo "$LOG_PREVIEW"
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
