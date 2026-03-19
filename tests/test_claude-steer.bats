#!/usr/bin/env bats
# test_claude-steer.bats — 测试 claude-steer.sh 输入注入功能
# 验证消息发送、steerLog 记录和 print 模式警告

load test_helper

STEER_SCRIPT="$SCRIPTS_DIR/claude-steer.sh"

# ── setup / teardown ─────────────────────────────────────────────────────────
setup() {
    setup_test_env
    setup_tmux_mock
    setup_other_mocks
}

teardown() {
    [[ -d "$TEST_TMP" ]] && rm -rf "$TEST_TMP"
}

# 辅助：以完整 mock 环境运行 steer 脚本
run_steer() {
    run env \
        CC_HOME="$CC_HOME" \
        CC_REGISTRY="$CC_REGISTRY" \
        MOCK_SESSIONS_DIR="$MOCK_SESSIONS_DIR" \
        bash -c "
            $(declare -f tmux); export -f tmux
            $(declare -f openclaw); export -f openclaw
            bash '$STEER_SCRIPT' $*
        "
}

# ═══════════════════════════════════════════════════════════════════════
# 参数验证
# ═══════════════════════════════════════════════════════════════════════

@test "claude-steer.sh 无参数时显示用法并退出 1" {
    run_steer
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage" ]]
}

@test "claude-steer.sh 只提供 task-id 缺少 message 时退出 1" {
    run_steer only-id
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# session 不存在
# ═══════════════════════════════════════════════════════════════════════

@test "claude-steer.sh session 不存在时退出 1 并输出 ERROR" {
    # 不调用 mock_session_alive，session 不存在
    run_steer dead-task '"纠偏消息"'
    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR" ]]
    [[ "$output" =~ "不存在" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# 消息发送成功（steerable 模式）
# ═══════════════════════════════════════════════════════════════════════

@test "claude-steer.sh session 存在时发送消息并输出确认" {
    add_registry_task "steer-ok" "running" "steerable"
    mock_session_alive "cc-steer-ok"

    run_steer steer-ok '"请专注登录模块"'
    [ "$status" -eq 0 ]
    [[ "$output" =~ "已发送消息" ]]
    [[ "$output" =~ "cc-steer-ok" ]]
}

@test "claude-steer.sh 发送后 steerLog 中新增一条记录" {
    add_registry_task "log-steer" "running" "steerable"
    mock_session_alive "cc-log-steer"

    env \
        CC_HOME="$CC_HOME" \
        CC_REGISTRY="$CC_REGISTRY" \
        MOCK_SESSIONS_DIR="$MOCK_SESSIONS_DIR" \
        bash -c "
            $(declare -f tmux); export -f tmux
            $(declare -f openclaw); export -f openclaw
            bash '$STEER_SCRIPT' log-steer '记录测试消息'
        " >/dev/null 2>&1

    local count
    count=$(jq '.[0].steerLog | length' "$CC_REGISTRY")
    [ "$count" -ge 1 ]

    local msg
    msg=$(jq -r '.[0].steerLog[-1].message' "$CC_REGISTRY")
    [[ "$msg" == "记录测试消息" ]]
}

@test "claude-steer.sh steerLog 时间戳字段存在且为正数" {
    add_registry_task "ts-steer" "running" "steerable"
    mock_session_alive "cc-ts-steer"

    env \
        CC_HOME="$CC_HOME" \
        CC_REGISTRY="$CC_REGISTRY" \
        MOCK_SESSIONS_DIR="$MOCK_SESSIONS_DIR" \
        bash -c "
            $(declare -f tmux); export -f tmux
            $(declare -f openclaw); export -f openclaw
            bash '$STEER_SCRIPT' ts-steer '时间戳测试'
        " >/dev/null 2>&1

    local at_ts
    at_ts=$(jq '.[0].steerLog[-1].at' "$CC_REGISTRY")
    [[ "$at_ts" =~ ^[0-9]+$ ]]
    [ "$at_ts" -gt 0 ]
}

# ═══════════════════════════════════════════════════════════════════════
# print 模式警告
# ═══════════════════════════════════════════════════════════════════════

@test "claude-steer.sh print 模式任务显示 WARNING 但不退出 1" {
    add_registry_task "print-task" "running" "print"
    mock_session_alive "cc-print-task"

    run_steer print-task '"steer a print task"'
    # print 模式下 steer 给出警告但仍执行（不退出 1）
    [ "$status" -eq 0 ]
    [[ "$output" =~ "WARNING" ]]
}

@test "claude-steer.sh print 模式警告中包含重新派发的建议" {
    add_registry_task "print-task2" "running" "print"
    mock_session_alive "cc-print-task2"

    run_steer print-task2 '"test"'
    [[ "$output" =~ "建议" ]] || [[ "$output" =~ "claude-kill" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# 无注册表时的行为
# ═══════════════════════════════════════════════════════════════════════

@test "claude-steer.sh 注册表不存在时仍能发送消息（不依赖注册表）" {
    rm -f "$CC_REGISTRY"
    mock_session_alive "cc-no-reg-steer"

    run_steer no-reg-steer '"消息"'
    # 无注册表时不记录 steerLog，但 send-keys 不应失败
    [ "$status" -eq 0 ]
    [[ "$output" =~ "已发送消息" ]]
}
