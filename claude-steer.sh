#!/bin/bash
# claude-steer.sh — 向正在运行的Claude Code发送消息（中途纠偏）
# 用法: claude-steer.sh <task-id> "<message>"

set -euo pipefail

TASK_ID="$1"
MESSAGE="$2"
TMUX_SESSION="claude-${TASK_ID}"

if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "ERROR: tmux session '$TMUX_SESSION' not found"
    exit 1
fi

# 发送消息到tmux session
tmux send-keys -t "$TMUX_SESSION" "$MESSAGE" Enter

echo "OK: sent message to '$TMUX_SESSION'"
