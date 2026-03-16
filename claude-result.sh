#!/bin/bash
# claude-result.sh — Get the full output of a completed task
# Usage: claude-result.sh <task-id>

set -euo pipefail

CLAWCLAU_HOME="${CLAWCLAU_HOME:-$HOME/.openclaw/workspace/.clawdbot}"
LOG_DIR="$CLAWCLAU_HOME/logs"

# --- Argument validation ---
if [ $# -lt 1 ]; then
    echo "Usage: claude-result.sh <task-id>"
    exit 1
fi

TASK_ID="$1"
LOG_FILE="$LOG_DIR/${TASK_ID}.log"
TMUX_SESSION="claude-${TASK_ID}"

# --- Dependency check ---
command -v tmux >/dev/null 2>&1 || { echo "ERROR: 'tmux' is required but not installed."; exit 1; }

if [ -f "$LOG_FILE" ]; then
    echo "=== Result for: $TASK_ID ==="
    cat "$LOG_FILE"
else
    echo "No log found for '$TASK_ID'"
    # If task is still running, capture current output from tmux
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        echo "Task is still running. Current output:"
        tmux capture-pane -t "$TMUX_SESSION" -p -S -
    fi
fi
