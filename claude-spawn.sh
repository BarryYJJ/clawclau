#!/bin/bash
# claude-spawn.sh — Spawn a Claude Code task in a tmux session
# Usage: claude-spawn.sh <task-id> "<prompt>" [workdir] [timeout-seconds]

set -euo pipefail

# --- Dependency check ---
for cmd in tmux jq; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: '$cmd' is required but not installed."; exit 1; }
done

# --- Configurable paths ---
CLAWCLAU_HOME="${CLAWCLAU_HOME:-$HOME/.openclaw/workspace/.clawdbot}"
TASK_REGISTRY="$CLAWCLAU_HOME/active-tasks.json"
LOG_DIR="$CLAWCLAU_HOME/logs"
CLAWCLAU_SHELL="${CLAWCLAU_SHELL:-bash}"

# --- Argument validation ---
if [ $# -lt 2 ]; then
    echo "Usage: claude-spawn.sh <task-id> \"<prompt>\" [workdir] [timeout-seconds]"
    exit 1
fi

TASK_ID="$1"
PROMPT="$2"
WORKDIR="${3:-$(pwd)}"
TIMEOUT="${4:-600}"

# --- Input sanitization (task-id: alphanumeric, dash, underscore only) ---
if ! echo "$TASK_ID" | grep -qE '^[a-zA-Z0-9_-]+$'; then
    echo "ERROR: task-id must be alphanumeric (a-z, A-Z, 0-9, -, _). Got: '$TASK_ID'"
    exit 1
fi

TMUX_SESSION="claude-${TASK_ID}"

# --- Init directories and registry ---
mkdir -p "$LOG_DIR"
[ -f "$TASK_REGISTRY" ] || echo '[]' > "$TASK_REGISTRY"

# --- Check for existing session ---
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "ERROR: tmux session '$TMUX_SESSION' already exists"
    exit 1
fi

# --- Write prompt to temp file and generate wrapper script ---
# This avoids the nightmare of nesting quotes through tmux → shell → claude.
PROMPT_FILE="$CLAWCLAU_HOME/prompts/${TASK_ID}.txt"
WRAPPER_FILE="$CLAWCLAU_HOME/prompts/${TASK_ID}.sh"
TASK_LOG_FILE="$LOG_DIR/${TASK_ID}.log"
mkdir -p "$CLAWCLAU_HOME/prompts" "$LOG_DIR"
printf '%s' "$PROMPT" > "$PROMPT_FILE"

# The wrapper just runs claude — no output redirection needed.
# Output capture is handled by tmux pipe-pane (see below).
cat > "$WRAPPER_FILE" << WRAPPER_EOF
#!/bin/bash
cd "\$2"
exec claude -p --dangerously-skip-permissions "\$(cat "\$1")"
WRAPPER_EOF
chmod +x "$WRAPPER_FILE"

# --- Launch Claude Code in tmux ---
# Uses login shell to ensure PATH and env vars are loaded.
# --dangerously-skip-permissions bypasses interactive approval — see SECURITY.md.
tmux new-session -d -s "$TMUX_SESSION" -c "$WORKDIR" \
    "$CLAWCLAU_SHELL -l $WRAPPER_FILE $PROMPT_FILE $WORKDIR $TASK_LOG_FILE"

# --- Capture terminal output via tmux pipe-pane ---
# This is the most reliable way to log claude output:
# - Works regardless of whether claude detects a TTY or not
# - Captures everything that appears in the terminal, including ANSI codes
# - Flushes in real-time (not buffered like shell redirection)
tmux pipe-pane -t "$TMUX_SESSION" "cat >> \"$TASK_LOG_FILE\""

# Verify the session actually started
sleep 1
if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    # Session died immediately — check if log was created for diagnostics
    if [ -f "$LOG_DIR/${TASK_ID}.log" ] && [ -s "$LOG_DIR/${TASK_ID}.log" ]; then
        echo "ERROR: tmux session '$TMUX_SESSION' started but exited immediately."
        echo "  Last log output:"
        tail -5 "$LOG_DIR/${TASK_ID}.log"
    else
        echo "ERROR: tmux session '$TMUX_SESSION' failed to start (no TTY or claude not found)."
    fi
    exit 1
fi

# --- Register task ---
TIMESTAMP=$(date +%s000)
jq --arg id "$TASK_ID" \
   --arg session "$TMUX_SESSION" \
   --arg prompt "$PROMPT" \
   --arg workdir "$WORKDIR" \
   --arg log "$LOG_DIR/${TASK_ID}.log" \
   --arg ts "$TIMESTAMP" \
   --arg timeout "$TIMEOUT" \
   '. += [{"id": $id, "tmuxSession": $session, "prompt": $prompt, "workdir": $workdir, "log": $log, "startedAt": ($ts|tonumber), "status": "running", "timeout": ($timeout|tonumber)}]' \
   "$TASK_REGISTRY" > "$TASK_REGISTRY.tmp" && mv "$TASK_REGISTRY.tmp" "$TASK_REGISTRY"

# --- Background monitor: auto-notify when task finishes ---
(
    # Source profile so openclaw is in PATH
    export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.openclaw/bin:$PATH"
    while tmux has-session -t "$TMUX_SESSION" 2>/dev/null; do
        sleep 10
    done
    # Session ended — wait for log flush
    sleep 2
    NOW_TS=$(date +%s000)
    if [ -s "$TASK_LOG_FILE" ]; then
        STATUS="done"
        EVENT_TEXT="Done: 任务 $TASK_ID 已完成"
    else
        STATUS="failed"
        EVENT_TEXT="Failed: 任务 $TASK_ID 失败（空日志）"
    fi
    # Update registry
    jq --arg id "$TASK_ID" --arg ts "$NOW_TS" --arg status "$STATUS" \
        '(.[] | select(.id == $id)) |= . + {status: $status, completedAt: ($ts | tonumber)}' \
        "$TASK_REGISTRY" > "$TASK_REGISTRY.tmp" && mv "$TASK_REGISTRY.tmp" "$TASK_REGISTRY"
    # Notify via openclaw
    openclaw system event --text "$EVENT_TEXT" --mode now 2>/dev/null || true
) &
disown

echo "OK: spawned '$TASK_ID' in tmux session '$TMUX_SESSION'"
echo "  Prompt: $PROMPT"
echo "  Workdir: $WORKDIR"
echo "  Log: $LOG_DIR/${TASK_ID}.log"
echo "  Timeout: ${TIMEOUT}s"
echo "  Monitor: background (auto-notify on completion)"
