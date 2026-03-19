#!/usr/bin/env bats
# test_claude-check.bats — 测试 claude-check.sh 状态查询输出格式
# 验证列表视图和单任务详情视图的输出内容

load test_helper

CHECK_SCRIPT="$SCRIPTS_DIR/claude-check.sh"

# ── setup / teardown ─────────────────────────────────────────────────────────
setup() {
    setup_test_env
    setup_tmux_mock
    setup_other_mocks
}

teardown() {
    [[ -d "$TEST_TMP" ]] && rm -rf "$TEST_TMP"
}

# 辅助：以完整 mock 环境运行 check 脚本
run_check() {
    run env \
        CC_HOME="$CC_HOME" \
        CC_REGISTRY="$CC_REGISTRY" \
        MOCK_SESSIONS_DIR="$MOCK_SESSIONS_DIR" \
        bash -c "
            $(declare -f tmux); export -f tmux
            $(declare -f openclaw); export -f openclaw
            bash '$CHECK_SCRIPT' $*
        "
}

# ═══════════════════════════════════════════════════════════════════════
# 注册表不存在的情况
# ═══════════════════════════════════════════════════════════════════════

@test "claude-check.sh 注册表文件不存在时提示用户并退出 0" {
    rm -f "$CC_REGISTRY"

    run_check
    [ "$status" -eq 0 ]
    [[ "$output" =~ "先运行" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# 列表视图（无参数）
# ═══════════════════════════════════════════════════════════════════════

@test "claude-check.sh 注册表为空时显示'暂无任务记录'" {
    run_check
    [ "$status" -eq 0 ]
    [[ "$output" =~ "暂无任务记录" ]]
}

@test "claude-check.sh 有任务时列表输出包含表头字段" {
    add_registry_task "list-task-1" "running"
    add_registry_task "list-task-2" "done"

    run_check
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ID" ]]
    [[ "$output" =~ "状态" ]]
    [[ "$output" =~ "list-task-1" ]]
    [[ "$output" =~ "list-task-2" ]]
}

@test "claude-check.sh 列表输出底部显示汇总统计行" {
    add_registry_task "t1" "done"
    add_registry_task "t2" "failed"

    run_check
    [ "$status" -eq 0 ]
    [[ "$output" =~ "汇总" ]]
    [[ "$output" =~ "已完成" ]]
}

@test "claude-check.sh 任务数量在标题中正确显示" {
    add_registry_task "cnt1" "running"
    add_registry_task "cnt2" "done"

    run_check
    [ "$status" -eq 0 ]
    # 标题含任务总数 2
    [[ "$output" =~ "2" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# 单任务详情视图
# ═══════════════════════════════════════════════════════════════════════

@test "claude-check.sh 查询存在任务显示任务详情区块" {
    add_registry_task "detail-task" "done"

    run_check detail-task
    [ "$status" -eq 0 ]
    [[ "$output" =~ "detail-task" ]]
    [[ "$output" =~ "状态" ]]
    [[ "$output" =~ "模式" ]]
    [[ "$output" =~ "日志" ]]
}

@test "claude-check.sh 查询不存在任务时退出 1 并输出 ERROR" {
    run_check no-such-task
    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR" ]]
    [[ "$output" =~ "no-such-task" ]]
}

@test "claude-check.sh 运行中任务（session 存活）状态显示为 running" {
    add_registry_task "live-task" "running"
    # 创建 mock session（模拟任务正在运行）
    mock_session_alive "cc-live-task"

    run_check live-task
    [ "$status" -eq 0 ]
    [[ "$output" =~ "running" ]]
}

@test "claude-check.sh 显示 steer 历史当任务有引导记录时" {
    add_registry_task "steer-hist" "done"
    add_task_steer_log "steer-hist" "调整方向测试"

    run_check steer-hist
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Steer 历史" ]]
    [[ "$output" =~ "调整方向测试" ]]
}

@test "claude-check.sh 任务有日志文件时显示结果摘要区块" {
    local log_file="$CC_LOG_DIR/log-task.json"
    printf '{"type":"result","subtype":"success","result":"测试结果内容"}\n' > "$log_file"
    add_registry_task "log-task" "done" "print" "$log_file"

    run_check log-task
    [ "$status" -eq 0 ]
    [[ "$output" =~ "结果摘要" ]]
}
