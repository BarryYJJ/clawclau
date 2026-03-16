#!/bin/bash
# claude-monitor.sh — Monitor all Claude Code tasks, auto-detect completion/timeout
# Recommended: run via cron every 2 minutes
# Usage: claude-monitor.sh

set -euo pipefail

CLAWCLAU_HOME="${CLAWCLAU_HOME:-$HOME/.openclaw/workspace/.clawdbot}"
TASK_REGISTRY="$CLAWCLAU_HOME/active-tasks.json"
LOG_DIR="$CLAWCLAU_HOME/logs"

# --- Dependency check ---
command -v tmux >/dev/null 2>&1 || { echo "ERROR: 'tmux' is required but not installed."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: 'jq' is required but not installed."; exit 1; }

# --- Check registry exists ---
if [ ! -f "$TASK_REGISTRY" ]; then
    exit 0
fi

# Get all running tasks
RUNNING_TASKS=$(jq -r '.[] | select(.status == "running") | .id' "$TASK_REGISTRY" 2>/dev/null)

if [ -z "$RUNNING_TASKS" ]; then
    exit 0
fi

for TASK_ID in $RUNNING_TASKS; do
    TMUX_SESSION="claude-${TASK_ID}"

    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        # Session still alive — check timeout
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
            # Notify via openclaw if available (optional dependency)
            command -v openclaw >/dev/null 2>&1 && \
                openclaw system event --text "Claude task '$TASK_ID' timed out after ${TIMEOUT}s" --mode now 2>/dev/null || true
        fi
    else
        # Session ended — check result
        LOG_FILE="$LOG_DIR/${TASK_ID}.log"
        if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
            STATUS="done"
        else
            STATUS="failed"
        fi

        TIMESTAMP=$(date +%s000)
        # Capture last part of log for preview (most useful output is at the end)
        RESULT=""
        [ -f "$LOG_FILE" ] && RESULT=$(tail -50 "$LOG_FILE" 2>/dev/null | tr '\n' ' ' | head -c 500)

        jq --arg id "$TASK_ID" --arg ts "$TIMESTAMP" --arg status "$STATUS" --arg result "$RESULT" \
           '(.[] | select(.id == $id)) |= . + {"status": $status, "completedAt": ($ts|tonumber), "result": $result}' \
           "$TASK_REGISTRY" > "$TASK_REGISTRY.tmp" && mv "$TASK_REGISTRY.tmp" "$TASK_REGISTRY"

        echo "COMPLETED: $TASK_ID — $STATUS"
        # Notify via openclaw if available (optional dependency)
        command -v openclaw >/dev/null 2>&1 && \
            openclaw system event --text "Claude task '$TASK_ID' completed with status: $STATUS" --mode now 2>/dev/null || true
    fi
done
