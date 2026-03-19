#!/usr/bin/env bats
# test_claude-result.bats — 测试 claude-result.sh 结果提取功能
# 验证 stream-json 解析、--raw 模式以及各种异常情况

load test_helper

RESULT_SCRIPT="$SCRIPTS_DIR/claude-result.sh"

# ── setup / teardown ─────────────────────────────────────────────────────────
setup() {
    setup_test_env
    setup_tmux_mock
    setup_other_mocks
}

teardown() {
    [[ -d "$TEST_TMP" ]] && rm -rf "$TEST_TMP"
}

# 辅助：以完整 mock 环境运行 result 脚本
run_result() {
    run env \
        CC_HOME="$CC_HOME" \
        CC_REGISTRY="$CC_REGISTRY" \
        CC_LOG_DIR="$CC_LOG_DIR" \
        MOCK_SESSIONS_DIR="$MOCK_SESSIONS_DIR" \
        bash -c "
            $(declare -f tmux); export -f tmux
            bash '$RESULT_SCRIPT' $*
        "
}

# ═══════════════════════════════════════════════════════════════════════
# 参数验证
# ═══════════════════════════════════════════════════════════════════════

@test "claude-result.sh 无参数时显示用法并退出 1" {
    run_result
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# 注册表/任务不存在
# ═══════════════════════════════════════════════════════════════════════

@test "claude-result.sh 注册表不存在时退出 1 并输出 ERROR" {
    rm -f "$CC_REGISTRY"

    run_result some-task
    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR" ]]
    [[ "$output" =~ "注册表" ]]
}

@test "claude-result.sh 任务不存在于注册表时退出 1" {
    run_result no-such-task
    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR" ]]
    [[ "$output" =~ "no-such-task" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# 正在运行任务（session 存活）
# ═══════════════════════════════════════════════════════════════════════

@test "claude-result.sh 任务正在运行时显示实时输出提示" {
    add_registry_task "running-task" "running"
    mock_session_alive "cc-running-task"

    run_result running-task
    [ "$status" -eq 0 ]
    [[ "$output" =~ "正在运行" ]]
    [[ "$output" =~ "running-task" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# 日志文件不存在
# ═══════════════════════════════════════════════════════════════════════

@test "claude-result.sh 日志文件不存在时退出 1 并输出 ERROR" {
    add_registry_task "no-log-task" "done" "print" "/nonexistent/log.json"

    run_result no-log-task
    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR" ]]
    [[ "$output" =~ "日志文件" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# 提取 stream-json 结果
# ═══════════════════════════════════════════════════════════════════════

@test "claude-result.sh 从 stream-json 日志提取 result 字段文本" {
    local log_file="$CC_LOG_DIR/result-task.json"
    printf '{"type":"result","subtype":"success","result":"提取的最终结果文本"}\n' > "$log_file"
    add_registry_task "result-task" "done" "print" "$log_file"

    run_result result-task
    [ "$status" -eq 0 ]
    [[ "$output" =~ "result-task" ]]
    [[ "$output" =~ "提取的最终结果文本" ]]
}

@test "claude-result.sh 从 stream-json 日志提取 assistant message 文本" {
    local log_file="$CC_LOG_DIR/asst-task.json"
    # 构造包含 assistant 消息的 stream-json
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"assistant 回复内容"}]}}\n' > "$log_file"
    add_registry_task "asst-task" "done" "print" "$log_file"

    run_result asst-task
    [ "$status" -eq 0 ]
    [[ "$output" =~ "assistant 回复内容" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# --raw 模式
# ═══════════════════════════════════════════════════════════════════════

@test "claude-result.sh --raw 输出原始日志内容" {
    local log_file="$CC_LOG_DIR/raw-task.json"
    printf '{"type":"raw","raw_data":"raw log line"}\n' > "$log_file"
    add_registry_task "raw-task" "done" "print" "$log_file"

    run_result raw-task --raw
    [ "$status" -eq 0 ]
    [[ "$output" =~ "raw_data" ]]
    [[ "$output" =~ "raw log line" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# 日志存在但无可提取文本的回退处理
# ═══════════════════════════════════════════════════════════════════════

@test "claude-result.sh 任务状态显示在输出头部" {
    # 基本验证：输出格式包含任务 ID 和状态
    local log_file="$CC_LOG_DIR/hdr-task.json"
    printf '{"type":"result","subtype":"success","result":"ok"}\n' > "$log_file"
    add_registry_task "hdr-task" "done" "print" "$log_file"

    run_result hdr-task
    [ "$status" -eq 0 ]
    # 头部格式为 "=== 任务 <id> [<status>] ==="
    [[ "$output" =~ "hdr-task" ]]
    [[ "$output" =~ "done" ]]
}
