#!/usr/bin/env bats
# test_clawclau-lib.bats — 测试 clawclau-lib.sh 中所有 cc_* 公共函数
# 说明：直接 source lib，在当前 shell 中测试各函数行为

load test_helper

# ── setup / teardown ─────────────────────────────────────────────────────────
setup() {
    setup_test_env      # 初始化 CC_HOME 等环境变量

    # 设置 mock 函数（tmux/openclaw 在 lib 的 cc_tmux_alive/cc_notify 中用到）
    setup_tmux_mock
    setup_other_mocks

    # 导入共享库（此时 CC_HOME 已指向临时目录）
    source "$SCRIPTS_DIR/clawclau-lib.sh"
}

teardown() {
    # 清理临时目录
    [[ -d "$TEST_TMP" ]] && rm -rf "$TEST_TMP"
}

# ═══════════════════════════════════════════════════════════════════════
# cc_init — 初始化目录和注册表
# ═══════════════════════════════════════════════════════════════════════

@test "cc_init 创建日志目录、Prompt 目录和注册表文件" {
    # 重置：删除 CC_HOME，验证 cc_init 能全量创建
    rm -rf "$CC_HOME"

    cc_init

    [ -d "$CC_LOG_DIR" ]
    [ -d "$CC_PROMPT_DIR" ]
    [ -f "$CC_REGISTRY" ]
    # 注册表内容应为空数组
    [[ "$(cat "$CC_REGISTRY")" == "[]" ]]
}

@test "cc_init 注册表已存在时不覆盖原有内容" {
    # 预先写入非空内容
    echo '[{"id":"existing"}]' > "$CC_REGISTRY"

    cc_init

    # 内容不能被覆盖为 []
    local content
    content=$(cat "$CC_REGISTRY")
    [[ "$content" == *'"existing"'* ]]
}

# ═══════════════════════════════════════════════════════════════════════
# cc_require — 依赖命令检查
# ═══════════════════════════════════════════════════════════════════════

@test "cc_require 所有命令存在时正常通过" {
    # bash 一定存在，验证不退出
    run bash -c "
        export CC_HOME='$CC_HOME'
        source '$SCRIPTS_DIR/clawclau-lib.sh'
        cc_require bash
    "
    [ "$status" -eq 0 ]
}

@test "cc_require 命令不存在时输出 ERROR 并退出 1" {
    run bash -c "
        export CC_HOME='$CC_HOME'
        source '$SCRIPTS_DIR/clawclau-lib.sh'
        cc_require __nonexistent_cmd_xyz_99__
    "
    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR" ]]
    [[ "$output" =~ "__nonexistent_cmd_xyz_99__" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# cc_task_get — 从注册表读取字段
# ═══════════════════════════════════════════════════════════════════════

@test "cc_task_get 返回存在任务的字段值" {
    add_registry_task "demo" "done"

    local result
    result=$(cc_task_get "demo" "status")
    [[ "$result" == "done" ]]
}

@test "cc_task_get 字段不存在时返回空字符串" {
    add_registry_task "demo"

    local result
    result=$(cc_task_get "demo" "nonexistent_field")
    [[ -z "$result" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# cc_task_exists — 检查任务是否存在
# ═══════════════════════════════════════════════════════════════════════

@test "cc_task_exists 任务存在时返回 0" {
    add_registry_task "exists-task"

    cc_task_exists "exists-task"
    [ $? -eq 0 ]
}

@test "cc_task_exists 任务不存在时返回非 0" {
    run bash -c "
        export CC_HOME='$CC_HOME'
        export CC_REGISTRY='$CC_REGISTRY'
        source '$SCRIPTS_DIR/clawclau-lib.sh'
        cc_task_exists 'no-such-task'
    "
    [ "$status" -ne 0 ]
}

# ═══════════════════════════════════════════════════════════════════════
# cc_task_register — 向注册表追加新任务
# ═══════════════════════════════════════════════════════════════════════

@test "cc_task_register 成功追加合法 JSON 任务" {
    local task_json='{"id":"new-task","status":"running","mode":"print"}'

    cc_task_register "$task_json"

    local count
    count=$(jq 'length' "$CC_REGISTRY")
    [ "$count" -eq 1 ]
    [[ "$(jq -r '.[0].id' "$CC_REGISTRY")" == "new-task" ]]
}

@test "cc_task_register 无效 JSON 返回 1 并输出 ERROR" {
    run bash -c "
        export CC_HOME='$CC_HOME'
        export CC_REGISTRY='$CC_REGISTRY'
        source '$SCRIPTS_DIR/clawclau-lib.sh'
        cc_task_register 'this is not json'
    "
    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# cc_task_update — 更新注册表中任务字段
# ═══════════════════════════════════════════════════════════════════════

@test "cc_task_update 成功更新指定任务的字段" {
    add_registry_task "upd-task" "running"

    cc_task_update "upd-task" '{"status":"done"}'

    local new_status
    new_status=$(jq -r '.[0].status' "$CC_REGISTRY")
    [[ "$new_status" == "done" ]]
}

@test "cc_task_update 无效 JSON patch 返回 1 并输出 ERROR" {
    add_registry_task "upd-task"

    run bash -c "
        export CC_HOME='$CC_HOME'
        export CC_REGISTRY='$CC_REGISTRY'
        source '$SCRIPTS_DIR/clawclau-lib.sh'
        cc_task_update 'upd-task' 'bad patch'
    "
    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# cc_task_steer_log — 向任务追加 steer 记录
# ═══════════════════════════════════════════════════════════════════════

@test "cc_task_steer_log 向已有 steerLog 追加记录" {
    add_registry_task "steer-task"
    add_task_steer_log "steer-task" "第一条"

    cc_task_steer_log "steer-task" "第二条"

    local count
    count=$(jq '.[0].steerLog | length' "$CC_REGISTRY")
    [ "$count" -eq 2 ]
    [[ "$(jq -r '.[0].steerLog[-1].message' "$CC_REGISTRY")" == "第二条" ]]
}

@test "cc_task_steer_log 无 steerLog 时创建数组并写入第一条记录" {
    add_registry_task "steer-task2"

    cc_task_steer_log "steer-task2" "首条消息"

    local msg
    msg=$(jq -r '.[0].steerLog[0].message' "$CC_REGISTRY")
    [[ "$msg" == "首条消息" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# cc_tmux_session — 生成 tmux session 名称
# ═══════════════════════════════════════════════════════════════════════

@test "cc_tmux_session 返回 cc-<id> 格式" {
    local result
    result=$(cc_tmux_session "my-task")
    [[ "$result" == "cc-my-task" ]]
}

@test "cc_tmux_session 含连字符和下划线的 ID" {
    local result
    result=$(cc_tmux_session "task_01-alpha")
    [[ "$result" == "cc-task_01-alpha" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# cc_tmux_alive — 检查 tmux session 存活
# ═══════════════════════════════════════════════════════════════════════

@test "cc_tmux_alive session 存在时返回 0" {
    # mock_session_alive 创建状态文件，使 mock tmux has-session 返回 0
    mock_session_alive "cc-alive-task"

    cc_tmux_alive "alive-task"
    [ $? -eq 0 ]
}

@test "cc_tmux_alive session 不存在时返回非 0" {
    run bash -c "
        export CC_HOME='$CC_HOME'
        export MOCK_SESSIONS_DIR='$MOCK_SESSIONS_DIR'
        $(declare -f tmux)
        export -f tmux
        source '$SCRIPTS_DIR/clawclau-lib.sh'
        cc_tmux_alive 'dead-task'
    "
    [ "$status" -ne 0 ]
}

# ═══════════════════════════════════════════════════════════════════════
# cc_extract_text — 从日志文件提取可读文本
# ═══════════════════════════════════════════════════════════════════════

@test "cc_extract_text 文件不存在时返回空字符串" {
    local result
    result=$(cc_extract_text "/nonexistent/path/file.json")
    [[ -z "$result" ]]
}

@test "cc_extract_text 从 stream-json 提取 result 字段内容" {
    local log_file="$CC_LOG_DIR/test.json"
    # 构造包含 result 的 stream-json 日志
    printf '{"type":"result","subtype":"success","result":"这是最终结果"}\n' > "$log_file"

    local result
    result=$(cc_extract_text "$log_file" 500)
    # jq 输出 JSON 字符串（含引号），用 =~ 做包含检查
    [[ "$result" =~ "这是最终结果" ]]
}

@test "cc_extract_text 从纯文本日志提取内容" {
    local log_file="$CC_LOG_DIR/test.txt"
    printf 'plain text output\nline two\n' > "$log_file"

    local result
    result=$(cc_extract_text "$log_file" 500)
    [[ "$result" =~ "plain text output" ]]
}

@test "cc_extract_text 空文件时返回空字符串" {
    local log_file="$CC_LOG_DIR/empty.json"
    touch "$log_file"  # 创建空文件

    local result
    result=$(cc_extract_text "$log_file")
    [[ -z "$result" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# cc_now_ms — 当前毫秒时间戳
# ═══════════════════════════════════════════════════════════════════════

@test "cc_now_ms 返回 13 位毫秒时间戳" {
    local ts
    ts=$(cc_now_ms)
    # 长度为 13 位
    [ "${#ts}" -eq 13 ]
    # 全为数字
    [[ "$ts" =~ ^[0-9]{13}$ ]]
}

# ═══════════════════════════════════════════════════════════════════════
# cc_elapsed_human — 人类可读的经过时长
# ═══════════════════════════════════════════════════════════════════════

@test "cc_elapsed_human 小于 60 秒时返回秒格式" {
    # 取 10 秒前的毫秒时间戳
    local start_ms
    start_ms=$(( $(date +%s000) - 10000 ))

    local result
    result=$(cc_elapsed_human "$start_ms")
    [[ "$result" =~ 秒$ ]]
}

@test "cc_elapsed_human 超过 60 秒时返回分钟格式" {
    # 取 130 秒前的毫秒时间戳
    local start_ms
    start_ms=$(( $(date +%s000) - 130000 ))

    local result
    result=$(cc_elapsed_human "$start_ms")
    [[ "$result" =~ 分钟$ ]]
}

# ═══════════════════════════════════════════════════════════════════════
# cc_validate_task_id — 验证任务 ID 格式
# ═══════════════════════════════════════════════════════════════════════

@test "cc_validate_task_id 合法 ID（字母数字连字符下划线）通过" {
    run bash -c "
        export CC_HOME='$CC_HOME'
        source '$SCRIPTS_DIR/clawclau-lib.sh'
        cc_validate_task_id 'my-task_01'
    "
    [ "$status" -eq 0 ]
}

@test "cc_validate_task_id 含特殊字符的 ID 退出 1 并输出 ERROR" {
    run bash -c "
        export CC_HOME='$CC_HOME'
        source '$SCRIPTS_DIR/clawclau-lib.sh'
        cc_validate_task_id 'bad task!'
    "
    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# cc_notify — 发送通知（静默成功测试，openclaw 已 mock）
# ═══════════════════════════════════════════════════════════════════════

@test "cc_notify 无 CC_NOTIFY_CHAT 时调用 openclaw system event 不报错" {
    unset CC_NOTIFY_CHAT
    run bash -c "
        export CC_HOME='$CC_HOME'
        $(declare -f openclaw)
        export -f openclaw
        source '$SCRIPTS_DIR/clawclau-lib.sh'
        cc_notify '测试通知'
    "
    [ "$status" -eq 0 ]
}

@test "cc_notify 设置 CC_NOTIFY_CHAT 时调用 openclaw message send 不报错" {
    run bash -c "
        export CC_HOME='$CC_HOME'
        export CC_NOTIFY_CHAT='test-channel'
        $(declare -f openclaw)
        export -f openclaw
        source '$SCRIPTS_DIR/clawclau-lib.sh'
        cc_notify '发送到 feishu'
    "
    [ "$status" -eq 0 ]
}
