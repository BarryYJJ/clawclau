#!/bin/bash
# claude-kill.sh — 终止一个Claude Code任务
# 用法: claude-kill.sh <task-id>

set -euo pipefail

TASK_ID="$1"
TMUX_SESSION="claude-${TASK_ID}"
TASK_REGISTRY="$HOME/.openclaw/workspace/.clawdbot/active-tasks.json"

if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    tmux kill-session -t "$TMUX_SESSION"
    echo "OK: killed tmux session '$TMUX_SESSION'"
else
    echo "Session '$TMUX_SESSION' not found (may already be done)"
fi

# 更新registry状态
TIMESTAMP=$(date +%s000)
jq --arg id "$TASK_ID" --arg ts "$TIMESTAMP" \
   '(.[] | select(.id == $id)) |= . + {"status": "killed", "killedAt": ($ts|tonumber)}' \
   "$TASK_REGISTRY" > "$TASK_REGISTRY.tmp" && mv "$TASK_REGISTRY.tmp" "$TASK_REGISTRY"
