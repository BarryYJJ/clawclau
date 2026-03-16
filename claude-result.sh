#!/bin/bash
# claude-result.sh — 获取已完成任务的完整输出
# 用法: claude-result.sh <task-id>

set -euo pipefail

TASK_ID="$1"
LOG_DIR="$HOME/.openclaw/workspace/.clawdbot/logs"
LOG_FILE="$LOG_DIR/${TASK_ID}.log"

if [ -f "$LOG_FILE" ]; then
    echo "=== Result for: $TASK_ID ==="
    cat "$LOG_FILE"
else
    echo "No log found for '$TASK_ID'"
    # 如果任务还在跑，尝试从tmux抓
    TMUX_SESSION="claude-${TASK_ID}"
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        echo "Task is still running. Capturing current output:"
        tmux capture-pane -t "$TMUX_SESSION" -p -S -
    fi
fi
