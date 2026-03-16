#!/bin/bash
# claude-kill.sh — Terminate a Claude Code task
# Usage: claude-kill.sh <task-id>

set -euo pipefail

CLAWCLAU_HOME="${CLAWCLAU_HOME:-$HOME/.openclaw/workspace/.clawdbot}"
TASK_REGISTRY="$CLAWCLAU_HOME/active-tasks.json"

# --- Dependency check ---
command -v tmux >/dev/null 2>&1 || { echo "ERROR: 'tmux' is required but not installed."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: 'jq' is required but not installed."; exit 1; }

# --- Argument validation ---
if [ $# -lt 1 ]; then
    echo "Usage: claude-kill.sh <task-id>"
    exit 1
fi

TASK_ID="$1"
TMUX_SESSION="claude-${TASK_ID}"

if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    tmux kill-session -t "$TMUX_SESSION"
    echo "OK: killed tmux session '$TMUX_SESSION'"
else
    echo "Session '$TMUX_SESSION' not found (may already be done)"
fi

# --- Update registry ---
if [ -f "$TASK_REGISTRY" ]; then
    TIMESTAMP=$(date +%s000)
    jq --arg id "$TASK_ID" --arg ts "$TIMESTAMP" \
       '(.[] | select(.id == $id)) |= . + {"status": "killed", "killedAt": ($ts|tonumber)}' \
       "$TASK_REGISTRY" > "$TASK_REGISTRY.tmp" && mv "$TASK_REGISTRY.tmp" "$TASK_REGISTRY"
fi
