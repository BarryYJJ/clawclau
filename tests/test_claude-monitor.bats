#!/usr/bin/env bats
# test_claude-monitor.bats — 测试 claude-monitor.sh 批量监控功能
# 验证超时检测、状态更新、session 存活判断等逻辑

load test_helper

MONITOR_SCRIPT="$SCRIPTS_DIR/claude-monitor.sh"

# ── setup / teardown ─────────────────────────────────────────────────────────
setup() {
    setup_test_env
    setup_tmux_mock
    setup_other_mocks
}

teardown() {
    [[ -d "$TEST_TMP" ]] && rm -rf "$TEST_TMP"
}

# 辅助：以完整 mock 环境运行 monitor 脚本
run_monitor() {
    run env \
        CC_HOME="$CC_HOME" \
        CC_REGISTRY="$CC_REGISTRY" \
        CC_LOG_DIR="$CC_LOG_DIR" \
        MOCK_SESSIONS_DIR="$MOCK_SESSIONS_DIR" \
        bash -c "
            $(declare -f tmux); export -f tmux
            $(declare -f openclaw); export -f openclaw
            $(declare -f sleep); export -f sleep
            bash '$MONITOR_SCRIPT'
        "
}

# ═══════════════════════════════════════════════════════════════════════
# 注册表不存在
# ═══════════════════════════════════════════════════════════════════════

@test "claude-monitor.sh 注册表不存在时输出跳过提示并退出 0" {
    rm -f "$CC_REGISTRY"

    run_monitor
    [ "$status" -eq 0 ]
    [[ "$output" =~ "注册表不存在" ]] || [[ "$output" =~ "跳过" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# 无 running 任务
# ═══════════════════════════════════════════════════════════════════════

@test "claude-monitor.sh 注册表为空时输出无运行中任务并退出 0" {
    run_monitor
    [ "$status" -eq 0 ]
    [[ "$output" =~ "无运行中任务" ]]
}

@test "claude-monitor.sh 所有任务均非 running 状态时退出 0" {
    add_registry_task "done-task" "done"
    add_registry_task "fail-task" "failed"

    run_monitor
    [ "$status" -eq 0 ]
    [[ "$output" =~ "无运行中任务" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# running 任务 session 已结束 → 更新为 done/failed
# ═══════════════════════════════════════════════════════════════════════

@test "claude-monitor.sh running 任务 session 已结束且日志非空时更新为 done" {
    local log_file="$CC_LOG_DIR/fin-task.json"
    printf '{"type":"result","result":"完成"}\n' > "$log_file"
    add_registry_task "fin-task" "running" "print" "$log_file"
    # 不创建 session（表示已结束）

    run_monitor
    [ "$status" -eq 0 ]

    local new_status
    new_status=$(jq -r '.[0].status' "$CC_REGISTRY")
    [[ "$new_status" == "done" ]]
}

@test "claude-monitor.sh running 任务 session 已结束且日志为空时更新为 failed" {
    local log_file="$CC_LOG_DIR/empty-task.json"
    touch "$log_file"  # 空日志文件
    add_registry_task "empty-task" "running" "print" "$log_file"
    # 不创建 session（表示已结束）

    run_monitor
    [ "$status" -eq 0 ]

    local new_status
    new_status=$(jq -r '.[0].status' "$CC_REGISTRY")
    [[ "$new_status" == "failed" ]]
}

@test "claude-monitor.sh 完成后任务有 completedAt 时间戳" {
    local log_file="$CC_LOG_DIR/ts-mon-task.json"
    printf '{"type":"result","result":"ok"}\n' > "$log_file"
    add_registry_task "ts-mon-task" "running" "print" "$log_file"

    env \
        CC_HOME="$CC_HOME" \
        CC_REGISTRY="$CC_REGISTRY" \
        CC_LOG_DIR="$CC_LOG_DIR" \
        MOCK_SESSIONS_DIR="$MOCK_SESSIONS_DIR" \
        bash -c "
            $(declare -f tmux); export -f tmux
            $(declare -f openclaw); export -f openclaw
            $(declare -f sleep); export -f sleep
            bash '$MONITOR_SCRIPT'
        " >/dev/null 2>&1

    local completed_at
    completed_at=$(jq -r '.[0].completedAt' "$CC_REGISTRY")
    [[ "$completed_at" =~ ^[0-9]+$ ]]
    [ "$completed_at" -gt 0 ]
}

# ═══════════════════════════════════════════════════════════════════════
# running 任务 session 存活 → 检查超时
# ═══════════════════════════════════════════════════════════════════════

@test "claude-monitor.sh session 存活未超时时输出 RUNNING 状态" {
    # 设置 startedAt 为当前时间（刚刚启动，未超时）
    local now_ts
    now_ts=$(date +%s000)
    add_registry_task "fresh-task" "running" "print" "$CC_LOG_DIR/fresh.json" "$now_ts"
    mock_session_alive "cc-fresh-task"

    run_monitor
    [ "$status" -eq 0 ]
    [[ "$output" =~ "RUNNING" ]]
    [[ "$output" =~ "fresh-task" ]]
}

@test "claude-monitor.sh session 存活已超时时终止 session 并更新为 timeout" {
    # 设置 startedAt 为 1000 秒前（超过默认 600s 超时）
    local old_ts
    old_ts=$(( $(date +%s000) - 1000000 ))
    add_registry_task "timeout-task" "running" "print" "$CC_LOG_DIR/to.json" "$old_ts"
    mock_session_alive "cc-timeout-task"

    run_monitor
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TIMEOUT" ]]

    local new_status
    new_status=$(jq -r '.[0].status' "$CC_REGISTRY")
    [[ "$new_status" == "timeout" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# 多任务混合场景
# ═══════════════════════════════════════════════════════════════════════

@test "claude-monitor.sh 同时处理多个任务并输出处理数量" {
    # 任务1：刚启动（session 存活）
    local now_ts
    now_ts=$(date +%s000)
    add_registry_task "multi-1" "running" "print" "$CC_LOG_DIR/m1.json" "$now_ts"
    mock_session_alive "cc-multi-1"

    # 任务2：session 已结束，有日志
    local log2="$CC_LOG_DIR/m2.json"
    printf '{"type":"result","result":"done"}\n' > "$log2"
    add_registry_task "multi-2" "running" "print" "$log2" "$now_ts"
    # 不创建 multi-2 session

    run_monitor
    [ "$status" -eq 0 ]
    # 输出应包含处理完成提示
    [[ "$output" =~ "Monitor 完成" ]]
}

@test "claude-monitor.sh 输出开始检查时间戳" {
    run_monitor
    [ "$status" -eq 0 ]
    [[ "$output" =~ "claude-monitor 开始检查" ]]
}
