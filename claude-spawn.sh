#!/bin/bash
# claude-spawn.sh — 在tmux中启动Claude Code任务
# 用法: claude-spawn.sh <task-id> "<prompt>" [workdir] [timeout-seconds]
#
# 小八调用乌萨奇的新方式：tmux + claude -p，绕过ACP
# 完成后自动关闭tmux session，monitor脚本检测到后更新注册表并通知小八

set -euo pipefail

TASK_ID="$1"
PROMPT="$2"
WORKDIR="${3:-$HOME/.openclaw/workspace}"
TIMEOUT="${4:-600}"  # 默认10分钟超时
TMUX_SESSION="claude-${TASK_ID}"
TASK_REGISTRY="$HOME/.openclaw/workspace/.clawdbot/active-tasks.json"
LOG_DIR="$HOME/.openclaw/workspace/.clawdbot/logs"

mkdir -p "$LOG_DIR"

# 检查是否已有同名session
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "ERROR: tmux session '$TMUX_SESSION' already exists"
    exit 1
fi

# 创建tmux session，运行claude命令后自动退出session
# 用login shell (-l) 确保PATH和env vars正确加载
tmux new-session -d -s "$TMUX_SESSION" -c "$WORKDIR" \
    "exec zsh -l -c 'claude -p --dangerously-skip-permissions \"${PROMPT}\" > \"${LOG_DIR}/${TASK_ID}.log\" 2>&1; exit'"

# 注册任务
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

echo "OK: spawned '$TASK_ID' in tmux session '$TMUX_SESSION'"
echo "  Prompt: $PROMPT"
echo "  Workdir: $WORKDIR"
echo "  Log: $LOG_DIR/${TASK_ID}.log"
echo "  Timeout: ${TIMEOUT}s"
