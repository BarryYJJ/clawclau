#!/usr/bin/env bash
# test_helper.bash — ClawClau 测试共享辅助函数
# 使用: load test_helper（在 bats 文件中）

# 脚本目录（相对于 tests/ 的父目录）
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"

# ── 初始化测试环境 ─────────────────────────────────────────────────────────
# 创建独立的临时目录，设置 CC_HOME 等环境变量
setup_test_env() {
    TEST_TMP="$(mktemp -d)"
    export TEST_TMP
    export CC_HOME="$TEST_TMP/clawclau"
    export CC_REGISTRY="$CC_HOME/active-tasks.json"
    export CC_LOG_DIR="$CC_HOME/logs"
    export CC_PROMPT_DIR="$CC_HOME/prompts"
    # 创建基础目录和空注册表
    mkdir -p "$CC_LOG_DIR" "$CC_PROMPT_DIR"
    echo '[]' > "$CC_REGISTRY"
}

# ── 有状态的 tmux mock（文件系统跟踪 session 存活状态）──────────────────────
setup_tmux_mock() {
    export MOCK_SESSIONS_DIR="$TEST_TMP/sessions"
    mkdir -p "$MOCK_SESSIONS_DIR"

    # 注意：函数中使用 $MOCK_SESSIONS_DIR，需要已导出
    tmux() {
        local cmd="${1:-}"
        shift || true
        local session="" prev=""
        case "$cmd" in
            has-session)
                # 解析 -t 参数
                while [[ $# -gt 0 ]]; do
                    [[ "$prev" == "-t" ]] && { session="$1"; break; }
                    prev="$1"; shift
                done
                [[ -f "${MOCK_SESSIONS_DIR}/${session}" ]] && return 0 || return 1
                ;;
            new-session)
                # 解析 -s 参数，创建 session 状态文件
                while [[ $# -gt 0 ]]; do
                    [[ "$prev" == "-s" ]] && {
                        session="$1"
                        touch "${MOCK_SESSIONS_DIR}/${session}"
                        break
                    }
                    prev="$1"; shift
                done
                return 0
                ;;
            kill-session)
                # 解析 -t 参数，删除 session 状态文件
                while [[ $# -gt 0 ]]; do
                    [[ "$prev" == "-t" ]] && { session="$1"; break; }
                    prev="$1"; shift
                done
                [[ -n "$session" ]] && rm -f "${MOCK_SESSIONS_DIR}/${session}"
                return 0
                ;;
            capture-pane)
                echo "${MOCK_TMUX_PANE:-mock pane output line 1}"
                return 0
                ;;
            list-panes|send-keys|pipe-pane|load-buffer|paste-buffer)
                return 0
                ;;
            *)
                return 0
                ;;
        esac
    }
    export -f tmux
}

# 手动创建"已存活"的 tmux session（模拟任务正在运行）
mock_session_alive() {
    local session="$1"
    touch "${MOCK_SESSIONS_DIR}/${session}"
}

# ── 其他命令 mock ─────────────────────────────────────────────────────────
setup_other_mocks() {
    # Mock claude（返回模拟 stream-json 结果）
    claude() {
        printf '{"type":"result","subtype":"success","result":"mock claude result"}\n'
        return 0
    }
    export -f claude

    # Mock openclaw（静默成功）
    openclaw() { return 0; }
    export -f openclaw

    # Mock sleep（立即返回，加速测试执行）
    sleep() { return 0; }
    export -f sleep
}

# ── 注册表辅助函数 ────────────────────────────────────────────────────────
# 向注册表添加一个测试任务
add_registry_task() {
    local id="${1:-test-task}"
    local status="${2:-running}"
    local mode="${3:-print}"
    local log="${4:-${CC_LOG_DIR}/${id}.json}"
    local started_ts="${5:-$(date +%s000)}"

    jq \
        --arg id       "$id" \
        --arg status   "$status" \
        --arg mode     "$mode" \
        --arg log      "$log" \
        --argjson ts   "$started_ts" \
        '. += [{
            id: $id,
            status: $status,
            mode: $mode,
            tmuxSession: ("cc-" + $id),
            prompt: "test prompt",
            workdir: "/tmp",
            log: $log,
            model: "",
            startedAt: $ts,
            timeout: 600,
            interval: 0,
            completedAt: null,
            maxRetries: 3,
            retryCount: 0,
            parentTaskId: null,
            steerLog: []
        }]' "$CC_REGISTRY" > "$CC_REGISTRY.tmp" \
    && mv "$CC_REGISTRY.tmp" "$CC_REGISTRY"
}

# 向任务追加 steer 历史记录
add_task_steer_log() {
    local id="$1"
    local msg="$2"
    local ts
    ts=$(date +%s000)
    jq \
        --arg id  "$id" \
        --arg msg "$msg" \
        --argjson ts "$ts" \
        '(.[] | select(.id == $id)) |= . + {
            steerLog: ((.steerLog // []) + [{at: $ts, message: $msg}])
        }' "$CC_REGISTRY" > "$CC_REGISTRY.tmp" \
    && mv "$CC_REGISTRY.tmp" "$CC_REGISTRY"
}
