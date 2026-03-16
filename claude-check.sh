#!/bin/bash
# claude-check.sh — 检查所有Claude Code任务状态
# 用法: claude-check.sh [task-id]

set -euo pipefail

TASK_REGISTRY="$HOME/.openclaw/workspace/.clawdbot/active-tasks.json"

if [ $# -gt 0 ]; then
    # 检查单个任务
    TASK_ID="$1"
    TMUX_SESSION="claude-${TASK_ID}"
    
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        STATUS="running"
        # 获取最后10行输出
        LAST_LINES=$(tmux capture-pane -t "$TMUX_SESSION" -p | tail -10)
    else
        STATUS="done"
        LAST_LINES=""
    fi
    
    # 从registry获取任务信息
    INFO=$(jq -r --arg id "$TASK_ID" '.[] | select(.id == $id) // empty' "$TASK_REGISTRY")
    
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
    # 检查所有任务
    echo "=== Active Claude Code Tasks ==="
    
    # 列出registry中的所有任务
    jq -r '.[] | "- \(.id) [\(.status)] tmux:\(.tmuxSession) started:\(.startedAt)"' "$TASK_REGISTRY" 2>/dev/null || echo "(no tasks)"
    
    echo ""
    echo "=== Live tmux sessions ==="
    tmux list-sessions 2>/dev/null | grep "^claude-" | while read line; do
        SESSION=$(echo "$line" | cut -d: -f1)
        TASK_ID="${SESSION#claude-}"
        echo "  $SESSION — $(tmux capture-pane -t "$SESSION" -p | tail -3 | tr '\n' ' ')"
    done || echo "  (none)"
fi
