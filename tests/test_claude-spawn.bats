#!/usr/bin/env bats
# test_claude-spawn.bats — 测试 claude-spawn.sh 参数解析与任务派发逻辑
# 所有 tmux/claude/sleep/openclaw 调用均使用 mock，不产生真实副作用

load test_helper

SPAWN_SCRIPT="$SCRIPTS_DIR/claude-spawn.sh"

# ── setup / teardown ─────────────────────────────────────────────────────────
setup() {
    setup_test_env
    setup_tmux_mock
    setup_other_mocks
}

teardown() {
    [[ -d "$TEST_TMP" ]] && rm -rf "$TEST_TMP"
}

# 辅助：以完整 mock 环境运行 spawn 脚本
run_spawn() {
    run env \
        CC_HOME="$CC_HOME" \
        CC_REGISTRY="$CC_REGISTRY" \
        CC_LOG_DIR="$CC_LOG_DIR" \
        CC_PROMPT_DIR="$CC_PROMPT_DIR" \
        MOCK_SESSIONS_DIR="$MOCK_SESSIONS_DIR" \
        bash -c "
            $(declare -f tmux)
            export -f tmux
            $(declare -f claude)
            export -f claude
            $(declare -f openclaw)
            export -f openclaw
            $(declare -f sleep)
            export -f sleep
            bash '$SPAWN_SCRIPT' $*
        "
}

# ═══════════════════════════════════════════════════════════════════════
# 参数验证
# ═══════════════════════════════════════════════════════════════════════

@test "claude-spawn.sh 无参数时显示用法并退出 1" {
    run_spawn
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage" ]]
}

@test "claude-spawn.sh 只有 task-id 没有 prompt 时退出 1" {
    run_spawn only-id
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage" ]]
}

@test "claude-spawn.sh 非法 task-id（含空格）退出 1" {
    run_spawn "'bad id'" '"test prompt"' "$TEST_TMP"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR" ]]
}

@test "claude-spawn.sh --timeout 为非数字时退出 1" {
    run_spawn --timeout abc task1 '"prompt"' "$TEST_TMP"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR" ]]
}

@test "claude-spawn.sh --timeout 为 0 时退出 1（需正整数）" {
    run_spawn --timeout 0 task1 '"prompt"' "$TEST_TMP"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR" ]]
}

@test "claude-spawn.sh 工作目录不存在时退出 1" {
    run_spawn task1 '"prompt"' "/nonexistent/workdir/xyz"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR" ]]
    [[ "$output" =~ "工作目录" ]]
}

@test "claude-spawn.sh 未知参数退出 1" {
    run_spawn --unknown-flag task1 '"prompt"'
    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# 成功派发：print 模式
# ═══════════════════════════════════════════════════════════════════════

@test "claude-spawn.sh 成功派发 print 模式任务，输出含'已派发'" {
    run env \
        CC_HOME="$CC_HOME" \
        MOCK_SESSIONS_DIR="$MOCK_SESSIONS_DIR" \
        bash -c "
            $(declare -f tmux); export -f tmux
            $(declare -f claude); export -f claude
            $(declare -f openclaw); export -f openclaw
            $(declare -f sleep); export -f sleep
            bash '$SPAWN_SCRIPT' spawn-test '测试 prompt' '$TEST_TMP'
        "
    [ "$status" -eq 0 ]
    [[ "$output" =~ "已派发: spawn-test" ]]
    [[ "$output" =~ "print" ]]
}

@test "claude-spawn.sh 派发后注册表中存在任务记录" {
    env \
        CC_HOME="$CC_HOME" \
        MOCK_SESSIONS_DIR="$MOCK_SESSIONS_DIR" \
        bash -c "
            $(declare -f tmux); export -f tmux
            $(declare -f claude); export -f claude
            $(declare -f openclaw); export -f openclaw
            $(declare -f sleep); export -f sleep
            bash '$SPAWN_SCRIPT' reg-test '测试 prompt' '$TEST_TMP'
        " >/dev/null 2>&1 || true

    # 检查注册表中有该任务
    local id
    id=$(jq -r '.[0].id // ""' "$CC_REGISTRY")
    [[ "$id" == "reg-test" ]]
}

@test "claude-spawn.sh 成功派发后创建 wrapper 脚本文件" {
    env \
        CC_HOME="$CC_HOME" \
        MOCK_SESSIONS_DIR="$MOCK_SESSIONS_DIR" \
        bash -c "
            $(declare -f tmux); export -f tmux
            $(declare -f claude); export -f claude
            $(declare -f openclaw); export -f openclaw
            $(declare -f sleep); export -f sleep
            bash '$SPAWN_SCRIPT' wrap-test 'prompt' '$TEST_TMP'
        " >/dev/null 2>&1 || true

    [ -f "$CC_PROMPT_DIR/wrap-test-wrapper.sh" ]
}

@test "claude-spawn.sh --steerable 模式输出含 steerable" {
    run env \
        CC_HOME="$CC_HOME" \
        MOCK_SESSIONS_DIR="$MOCK_SESSIONS_DIR" \
        bash -c "
            $(declare -f tmux); export -f tmux
            $(declare -f claude); export -f claude
            $(declare -f openclaw); export -f openclaw
            $(declare -f sleep); export -f sleep
            bash '$SPAWN_SCRIPT' --steerable steer-test 'prompt' '$TEST_TMP'
        "
    [ "$status" -eq 0 ]
    [[ "$output" =~ "steerable" ]]
}

@test "claude-spawn.sh 相同 task-id 重复派发时退出 1" {
    # 先派发一次
    env \
        CC_HOME="$CC_HOME" \
        MOCK_SESSIONS_DIR="$MOCK_SESSIONS_DIR" \
        bash -c "
            $(declare -f tmux); export -f tmux
            $(declare -f claude); export -f claude
            $(declare -f openclaw); export -f openclaw
            $(declare -f sleep); export -f sleep
            bash '$SPAWN_SCRIPT' dup-task 'prompt' '$TEST_TMP'
        " >/dev/null 2>&1 || true

    # 再次派发相同 ID，应失败
    run env \
        CC_HOME="$CC_HOME" \
        MOCK_SESSIONS_DIR="$MOCK_SESSIONS_DIR" \
        bash -c "
            $(declare -f tmux); export -f tmux
            $(declare -f claude); export -f claude
            $(declare -f openclaw); export -f openclaw
            $(declare -f sleep); export -f sleep
            bash '$SPAWN_SCRIPT' dup-task 'prompt' '$TEST_TMP'
        "
    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR" ]]
}

@test "claude-spawn.sh --interval 选项在输出中显示进度汇报间隔" {
    run env \
        CC_HOME="$CC_HOME" \
        MOCK_SESSIONS_DIR="$MOCK_SESSIONS_DIR" \
        bash -c "
            $(declare -f tmux); export -f tmux
            $(declare -f claude); export -f claude
            $(declare -f openclaw); export -f openclaw
            $(declare -f sleep); export -f sleep
            bash '$SPAWN_SCRIPT' --interval 60 intv-test 'prompt' '$TEST_TMP'
        "
    [ "$status" -eq 0 ]
    [[ "$output" =~ "60s" ]]
}
