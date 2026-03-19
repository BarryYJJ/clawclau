#!/usr/bin/env bats
# test_claude-kill.bats — 测试 claude-kill.sh 终止任务逻辑
# 验证 tmux session 终止、注册表状态更新和各种边界条件

load test_helper

KILL_SCRIPT="$SCRIPTS_DIR/claude-kill.sh"

# ── setup / teardown ─────────────────────────────────────────────────────────
setup() {
    setup_test_env
    setup_tmux_mock
    setup_other_mocks
}

teardown() {
    [[ -d "$TEST_TMP" ]] && rm -rf "$TEST_TMP"
}

# 辅助：以完整 mock 环境运行 kill 脚本
run_kill() {
    run env \
        CC_HOME="$CC_HOME" \
        CC_REGISTRY="$CC_REGISTRY" \
        MOCK_SESSIONS_DIR="$MOCK_SESSIONS_DIR" \
        bash -c "
            $(declare -f tmux); export -f tmux
            $(declare -f openclaw); export -f openclaw
            bash '$KILL_SCRIPT' $*
        "
}

# ═══════════════════════════════════════════════════════════════════════
# 参数验证
# ═══════════════════════════════════════════════════════════════════════

@test "claude-kill.sh 无参数时显示用法并退出 1" {
    run_kill
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# session 不存在（任务已完成）
# ═══════════════════════════════════════════════════════════════════════

@test "claude-kill.sh session 不存在时提示任务可能已完成" {
    add_registry_task "dead-task" "done"
    # 不调用 mock_session_alive，session 不存在

    run_kill dead-task
    [ "$status" -eq 0 ]
    [[ "$output" =~ "不存在" ]]
}

@test "claude-kill.sh session 不存在时仍更新注册表状态为 killed" {
    add_registry_task "ghost-task" "running"

    run_kill ghost-task
    [ "$status" -eq 0 ]

    local status_val
    status_val=$(jq -r '.[0].status' "$CC_REGISTRY")
    [[ "$status_val" == "killed" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# session 存在（任务正在运行）
# ═══════════════════════════════════════════════════════════════════════

@test "claude-kill.sh session 存在时终止 session 并输出确认" {
    add_registry_task "alive-task" "running"
    mock_session_alive "cc-alive-task"

    run_kill alive-task
    [ "$status" -eq 0 ]
    [[ "$output" =~ "已终止" ]]
    [[ "$output" =~ "cc-alive-task" ]]
}

@test "claude-kill.sh 终止后注册表状态更新为 killed" {
    add_registry_task "kill-me" "running"
    mock_session_alive "cc-kill-me"

    env \
        CC_HOME="$CC_HOME" \
        CC_REGISTRY="$CC_REGISTRY" \
        MOCK_SESSIONS_DIR="$MOCK_SESSIONS_DIR" \
        bash -c "
            $(declare -f tmux); export -f tmux
            $(declare -f openclaw); export -f openclaw
            bash '$KILL_SCRIPT' kill-me
        " >/dev/null 2>&1

    local status_val
    status_val=$(jq -r '.[0].status' "$CC_REGISTRY")
    [[ "$status_val" == "killed" ]]
}

@test "claude-kill.sh 终止后注册表包含 killedAt 时间戳" {
    add_registry_task "ts-task" "running"
    mock_session_alive "cc-ts-task"

    env \
        CC_HOME="$CC_HOME" \
        CC_REGISTRY="$CC_REGISTRY" \
        MOCK_SESSIONS_DIR="$MOCK_SESSIONS_DIR" \
        bash -c "
            $(declare -f tmux); export -f tmux
            $(declare -f openclaw); export -f openclaw
            bash '$KILL_SCRIPT' ts-task
        " >/dev/null 2>&1

    local killed_at
    killed_at=$(jq -r '.[0].killedAt' "$CC_REGISTRY")
    # killedAt 应为正数时间戳
    [[ "$killed_at" =~ ^[0-9]+$ ]]
    [ "$killed_at" -gt 0 ]
}

# ═══════════════════════════════════════════════════════════════════════
# 注册表不存在的边界情况
# ═══════════════════════════════════════════════════════════════════════

@test "claude-kill.sh 注册表不存在时仅执行 tmux kill，不报错" {
    rm -f "$CC_REGISTRY"
    mock_session_alive "cc-no-reg"

    run_kill no-reg
    # 无注册表时脚本应仍能正常运行（终止 session）
    [ "$status" -eq 0 ]
}
