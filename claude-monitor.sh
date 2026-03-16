#!/bin/bash
# claude-monitor.sh — 监控所有Claude Code任务，完成后自动更新状态并通知
# 建议通过cron每2分钟运行一次
# 用法: claude-monitor.sh

set -euo pipefail

TASK_REGISTRY="$HOME/.openclaw/workspace/.clawdbot/active-tasks.json"
LOG_DIR="$HOME/.openclaw/workspace/.clawdbot/logs"

# 获取所有running状态的任务
RUNNING_TASKS=$(jq -r '.[] | select(.status == "running") | .id' "$TASK_REGISTRY" 2>/dev/null)

if [ -z "$RUNNING_TASKS" ]; then
    exit 0
fi

for TASK_ID in $RUNNING_TASKS; do
    TMUX_SESSION="claude-${TASK_ID}"
    
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        # 检查是否超时
        STARTED=$(jq -r --arg id "$TASK_ID" '.[] | select(.id == $id) | .startedAt' "$TASK_REGISTRY")
        TIMEOUT=$(jq -r --arg id "$TASK_ID" '.[] | select(.id == $id) | .timeout' "$TASK_REGISTRY")
        NOW=$(date +%s000)
        ELAPSED=$(( (NOW - STARTED) / 1000 ))
        
        if [ "$ELAPSED" -gt "$TIMEOUT" ]; then
            echo "TIMEOUT: $TASK_ID (elapsed ${ELAPSED}s > timeout ${TIMEOUT}s)"
            tmux kill-session -t "$TMUX_SESSION" 2>/dev/null
            TIMESTAMP=$(date +%s000)
            jq --arg id "$TASK_ID" --arg ts "$TIMESTAMP" \
               '(.[] | select(.id == $id)) |= . + {"status": "timeout", "completedAt": ($ts|tonumber)}' \
               "$TASK_REGISTRY" > "$TASK_REGISTRY.tmp" && mv "$TASK_REGISTRY.tmp" "$TASK_REGISTRY"
            openclaw system event --text "Claude task '$TASK_ID' timed out after ${TIMEOUT}s" --mode now 2>/dev/null || true
        fi
    else
        # Session已结束，检查结果
        LOG_FILE="$LOG_DIR/${TASK_ID}.log"
        if [ -f "$LOG_FILE" ]; then
            # 如果log有内容就认为成功（claude -p有输出=正常完成）
            if [ -s "$LOG_FILE" ]; then
                STATUS="done"
            else
                STATUS="failed"
            fi
            
            TIMESTAMP=$(date +%s000)
            RESULT=$(head -50 "$LOG_FILE" | tr '\n' ' ' | head -c 500)
            
            jq --arg id "$TASK_ID" --arg ts "$TIMESTAMP" --arg status "$STATUS" --arg result "$RESULT" \
               '(.[] | select(.id == $id)) |= . + {"status": $status, "completedAt": ($ts|tonumber), "result": $result}' \
               "$TASK_REGISTRY" > "$TASK_REGISTRY.tmp" && mv "$TASK_REGISTRY.tmp" "$TASK_REGISTRY"
            
            echo "COMPLETED: $TASK_ID — $STATUS"
            # 通知小八
            openclaw system event --text "Claude task '$TASK_ID' completed with status: $STATUS. Result preview: ${RESULT:0:200}" --mode now 2>/dev/null || true
        else
            TIMESTAMP=$(date +%s000)
            jq --arg id "$TASK_ID" --arg ts "$TIMESTAMP" \
               '(.[] | select(.id == $id)) |= . + {"status": "no-log", "completedAt": ($ts|tonumber)}' \
               "$TASK_REGISTRY" > "$TASK_REGISTRY.tmp" && mv "$TASK_REGISTRY.tmp" "$TASK_REGISTRY"
        fi
    fi
done
