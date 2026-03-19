# ClawClau v2

**Task dispatcher for Claude Code via tmux**

ClawClau 是一套基于 tmux 的异步 Claude Code 任务调度工具集，专为 OpenClaw 小八等 AI Agent 设计。支持在不阻塞主进程的情况下派发、监控、纠偏和获取 Claude Code 任务结果。

---

## 快速开始

```bash
# 方式一：git clone 后运行安装脚本（推荐）
git clone https://github.com/BarryYJJ/clawclau.git
cd clawclau
./install.sh

# 方式二：curl 一键安装
curl -fsSL https://raw.githubusercontent.com/BarryYJJ/clawclau/main/install.sh | bash
```

安装完成后验证：

```bash
~/.openclaw/workspace/scripts/claude-check.sh
```

---

## 安装

### 依赖清单

**必选：**

| 依赖 | 版本要求 | 说明 |
|------|---------|------|
| [tmux](https://github.com/tmux/tmux) | >= 3.0 | 任务隔离执行环境 |
| [jq](https://stedolan.github.io/jq/) | >= 1.6 | 注册表 JSON 操作 |
| [claude](https://github.com/anthropics/claude-code) | 最新版 | Claude Code CLI |

**可选：**

| 依赖 | 说明 |
|------|------|
| [openclaw](https://github.com/BarryYJJ/openclaw) | 通知功能（cc_notify）；未安装时通知静默失败 |
| python3 + yfinance | morning-brief.sh 的美股数据获取 |

```bash
# macOS
brew install tmux jq
npm install -g @anthropic-ai/claude-code

# Linux (Debian/Ubuntu)
sudo apt install tmux jq
npm install -g @anthropic-ai/claude-code
```

### 安装 ClawClau

```bash
git clone https://github.com/BarryYJJ/clawclau.git
cd clawclau
./install.sh
```

`install.sh` 会自动完成：
- 检查依赖并给出安装提示
- 创建 `~/.clawclau/` 数据目录结构
- 生成默认配置文件 `~/.clawclau/config`
- 复制脚本到 `~/.openclaw/workspace/scripts/`
- 安装 skill 到 `~/.openclaw/workspace/skills/clawclau/`

卸载：

```bash
./uninstall.sh
```

---

## 使用方法

所有脚本均位于 `scripts/` 目录，下文以 `$SCRIPTS` 代指该路径。

```bash
SCRIPTS=~/.openclaw/workspace/clawclau/scripts
```

### spawn — 派发任务

```bash
$SCRIPTS/claude-spawn.sh [OPTIONS] <task-id> "<prompt>" [workdir]
```

**选项：**

| 选项 | 默认值 | 说明 |
|------|--------|------|
| `--steerable` | false | 交互式模式，支持 `claude-steer.sh` 中途纠偏 |
| `--timeout <sec>` | 600 | 超时秒数 |
| `--interval <sec>` | 0 | 进度汇报间隔（0 = 关闭） |
| `--max-retries <n>` | 3 | 最大重试次数记录 |
| `--model <name>` | — | 指定 Claude 模型（如 `claude-opus-4-6`） |
| `--parent <id>` | — | 父任务 ID（重试时使用） |

**示例：**

```bash
# 基础任务（print 模式，stream-json 日志）
$SCRIPTS/claude-spawn.sh kb-update "请将以下文章整理入知识库..." ~/workspace

# 带进度汇报，每 60s 通知一次
$SCRIPTS/claude-spawn.sh research "调研 AI Agent 框架趋势" ~/workspace \
  --interval 60 --timeout 1200

# 交互式模式（可中途发消息纠偏）
$SCRIPTS/claude-spawn.sh explore "探索代码库，找出主要问题" ~/myproject \
  --steerable --interval 120

# 指定模型
$SCRIPTS/claude-spawn.sh heavy "复杂分析任务..." ~/workspace \
  --model claude-opus-4-6 --timeout 1800

# 重试（改进 prompt 后重新派发）
$SCRIPTS/claude-spawn.sh kb-update-retry-1 "改进后的 prompt..." ~/workspace \
  --parent kb-update --retry-count 1
```

任务派发后，后台自动启动完成检测器。任务结束时通过 `openclaw system event` 通知小八，无需手动轮询。

---

### check — 查询状态

```bash
$SCRIPTS/claude-check.sh              # 列出所有任务（表格）
$SCRIPTS/claude-check.sh <task-id>   # 单任务详情 + 结果预览
```

**确定性检查**：以 tmux session 是否存活为 running 的最终判据，不调用 AI，不消耗 token。

```
══ ClawClau 任务列表 (3 条) ═══════════════
ID                       状态         重试     超时    开始时间
──────────────────────────────────────────────────────
kb-update                done         0/3      600s    03-19 09:00
research                 running      0/3      1200s   03-19 09:15
explore                  killed       0/3      600s    03-18 22:00

汇总: 1 运行中, 1 已完成, 0 失败/超时
```

---

### result — 获取结果

```bash
$SCRIPTS/claude-result.sh <task-id>        # 提取可读文本（推荐）
$SCRIPTS/claude-result.sh <task-id> --raw  # 输出原始 stream-json 日志
```

- 任务还在运行时，实时抓取 tmux 屏幕输出
- Print 模式自动解析 stream-json，优先级：`result` > `assistant message` > `text_delta`

---

### kill — 终止任务

```bash
$SCRIPTS/claude-kill.sh <task-id>
```

终止对应的 tmux session 并将注册表状态更新为 `killed`。

---

### steer — 中途纠偏

```bash
$SCRIPTS/claude-steer.sh <task-id> "请聚焦在 X 方面，忽略 Y"
```

通过 `tmux send-keys` 向交互式 Claude 发送消息。**仅支持 `--steerable` 模式**；print 模式（`claude -p`）非交互，无法 steer，建议 kill 后以改进 prompt 重新派发。

每次 steer 消息自动记录到注册表的 `steerLog` 数组，可通过 `claude-check.sh <id>` 查看历史。

---

### monitor — 批量监控（cron）

```bash
$SCRIPTS/claude-monitor.sh
```

作为 spawn 内嵌后台 completion detector 的**安全兜底**：

- 检查所有 `running` 任务的 tmux session 是否存活
- session 结束后更新状态（done/failed）并通知小八
- 检查超时，超时后终止 session

**推荐设置 cron，每 10 分钟运行一次：**

```bash
# crontab -e
*/10 * * * * /path/to/clawclau/scripts/claude-monitor.sh >> /tmp/clawclau-monitor.log 2>&1
```

---

### morning-brief — 每日早报

```bash
$SCRIPTS/morning-brief.sh
```

生成包含美股/A股/港股指数、核心标的涨跌和 AI 要闻的每日早报。依赖 `python3`，可选安装 `yfinance` 获取更稳定的美股数据。

---

## 架构说明

```
scripts/
├── clawclau-lib.sh        # 共享库（所有脚本 source 此文件）
├── claude-spawn.sh        # 派发任务
├── claude-check.sh        # 查询状态（确定性，不耗 token）
├── claude-result.sh       # 获取结果
├── claude-kill.sh         # 终止任务
├── claude-steer.sh        # 中途纠偏
├── claude-monitor.sh      # 批量监控（cron 用）
└── morning-brief.sh       # 每日早报生成器

skills/
└── clawclau/
    └── SKILL.md           # OpenClaw skill 描述文件（小八调用指南）

tests/
├── test_helper.bash       # 测试共享辅助函数（tmux/openclaw mock）
├── test_clawclau-lib.bats
├── test_claude-spawn.bats
├── test_claude-check.bats
├── test_claude-result.bats
├── test_claude-kill.bats
├── test_claude-steer.bats
└── test_claude-monitor.bats
```

### clawclau-lib.sh — 共享库

所有脚本通过 `source clawclau-lib.sh` 引入共享功能：

| 函数 | 说明 |
|------|------|
| `cc_init` | 初始化目录结构和注册表 |
| `cc_require <cmd>...` | 检查依赖命令是否安装 |
| `cc_task_get <id> <field>` | 读取注册表字段 |
| `cc_task_exists <id>` | 检查任务是否存在 |
| `cc_task_register <json>` | 追加新任务到注册表 |
| `cc_task_update <id> <patch>` | 更新注册表字段 |
| `cc_task_steer_log <id> <msg>` | 追加 steer 记录 |
| `cc_tmux_session <id>` | 生成 tmux session 名（`cc-<id>`） |
| `cc_extract_text <log> [max]` | 从 stream-json 或纯文本日志提取摘要 |
| `cc_notify <text>` | 发送通知（飞书群或 openclaw event） |
| `cc_now_ms` | 当前毫秒时间戳 |
| `cc_elapsed_human <start_ms>` | 人类可读经过时长 |
| `cc_validate_task_id <id>` | 验证任务 ID 格式 |

### 两种运行模式

| 模式 | 命令 | 日志格式 | 支持 steer | 适用场景 |
|------|------|----------|-----------|---------|
| **Print**（默认）| `claude -p --output-format stream-json` | `.json` | 否 | 任务明确，一次完成 |
| **Steerable** | `claude --dangerously-skip-permissions` | `.txt` | 是 | 探索性任务，需中途纠正 |

### 任务状态流转

```
running
  → done        (session 结束，日志非空)
  → failed      (session 结束，日志为空)
  → timeout     (超过 --timeout 秒)
  → killed      (手动 claude-kill.sh)
```

---

## 配置说明

### 数据目录：`~/.clawclau/`

```
~/.clawclau/
├── active-tasks.json      # 任务注册表（source of truth）
├── config                 # 可选配置文件
├── logs/
│   ├── <task-id>.json     # stream-json 日志（print 模式）
│   └── <task-id>.txt      # 纯文本日志（steerable 模式）
└── prompts/
    ├── <task-id>.txt      # prompt 备份
    └── <task-id>-wrapper.sh  # 自动生成的 wrapper 脚本
```

### 配置文件：`~/.clawclau/config`

```ini
# 飞书通知目标（群 ID 或机器人 webhook）
# 留空则使用 openclaw system event 通知
notify_chat = your-feishu-chat-id
```

**配置飞书通知（可选）：**

1. 打开飞书，进入目标群 → 群设置 → 群机器人 → 复制群 ID
2. 编辑配置文件：

```bash
# 编辑配置文件，填入群 ID
vim ~/.clawclau/config
# 取消注释并填写 notify_chat = oc_xxxxxxxxxxxxxxxx
```

3. 也可通过环境变量临时覆盖：

```bash
CC_NOTIFY_CHAT=oc_xxxxxxxxxxxxxxxx $SCRIPTS/claude-spawn.sh my-task "..." .
```

不配置时，`cc_notify` 会回退到 `openclaw system event` 通知（需要 openclaw CLI）。

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CC_HOME` | `~/.clawclau` | 数据目录（注册表、日志、prompts）|
| `CC_NOTIFY_CHAT` | — | 飞书通知目标（覆盖 config 文件） |

**示例：**

```bash
# 临时覆盖数据目录（用于测试）
CC_HOME=/tmp/test-clawclau $SCRIPTS/claude-spawn.sh test "hello" .

# 指定飞书通知目标
CC_NOTIFY_CHAT=my-feishu-group $SCRIPTS/claude-spawn.sh my-task "..." .
```

---

## 运行测试

测试使用 [bats-core](https://github.com/bats-core/bats-core)：

```bash
brew install bats-core
bats tests/
```

---

## 注册表字段说明（active-tasks.json）

```json
{
  "id":           "任务唯一 ID",
  "mode":         "print | steerable",
  "tmuxSession":  "cc-{id}",
  "prompt":       "完整 prompt",
  "workdir":      "工作目录",
  "log":          "日志文件路径",
  "model":        "模型名称（空=默认）",
  "startedAt":    1234567890000,
  "timeout":      600,
  "interval":     0,
  "status":       "running | done | failed | timeout | killed",
  "completedAt":  null,
  "maxRetries":   3,
  "retryCount":   0,
  "parentTaskId": null,
  "steerLog":     []
}
```

---

## 设计原则

1. **确定性监控**：tmux 存活 + 日志文件检查，不靠 AI 轮询，零 token 消耗
2. **隔离执行**：每个任务独立 tmux session（`cc-<id>`），互不干扰
3. **内嵌完成检测**：spawn 时启动后台双重 fork 进程，session 结束即通知
4. **stream-json 日志**：实时写入，可提取中间进度和最终结果
5. **小八主导重试**：失败通知小八，由小八决策 prompt 如何改进后重新派发
