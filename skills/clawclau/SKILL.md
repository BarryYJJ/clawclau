# ClawClau — Claude Code 任务调度系统

小八（OpenClaw）派发异步 Claude Code 任务的工具集。基于 Elvis Sun 的 Agent Swarm 架构设计。

## 核心文件

```
~/.openclaw/workspace/scripts/
├── clawclau-lib.sh        # 共享库（所有脚本 source 此文件）
├── claude-spawn.sh        # 派发任务
├── claude-check.sh        # 查询状态（确定性，不耗 token）
├── claude-result.sh       # 获取结果
├── claude-monitor.sh      # 批量监控（cron 用）
├── claude-kill.sh         # 终止任务
└── claude-steer.sh        # 中途纠偏

~/.clawclau/
├── active-tasks.json      # 任务注册表（source of truth）
├── logs/
│   ├── task-id.json       # stream-json 格式日志（print 模式）
│   └── task-id.txt        # 纯文本日志（steerable 模式）
└── prompts/
    ├── task-id.txt        # prompt 备份
    └── task-id-wrapper.sh # 自动生成的 wrapper 脚本
```

## 快速开始

```bash
SCRIPTS=~/.openclaw/workspace/scripts

# 1. 派发任务（print 模式，stream-json 日志）
$SCRIPTS/claude-spawn.sh my-task "请整理这份文档..." /path/to/workdir

# 2. 查看所有任务
$SCRIPTS/claude-check.sh

# 3. 查看单个任务详情 + 结果预览
$SCRIPTS/claude-check.sh my-task

# 4. 获取完整结果
$SCRIPTS/claude-result.sh my-task

# 5. 终止任务
$SCRIPTS/claude-kill.sh my-task
```

## 脚本详解

### claude-spawn.sh — 派发任务

```bash
claude-spawn.sh [OPTIONS] <task-id> "<prompt>" [workdir]

# 选项
--steerable        交互式模式（支持 claude-steer.sh 纠偏）
--timeout <sec>    超时秒数（默认 600，即 10 分钟）
--interval <sec>   进度汇报间隔，0=关闭（默认 0）
--max-retries <n>  最大重试次数记录（默认 3）
--model <name>     Claude 模型名称（如 claude-opus-4-6）
--parent <id>      父任务 ID（重试时使用）
--retry-count <n>  当前重试计数（内部使用）
```

**示例：**

```bash
SCRIPTS=~/.openclaw/workspace/scripts

# 基础任务，workdir 默认当前目录
$SCRIPTS/claude-spawn.sh kb-update "请将以下文章入库..." ~/.openclaw/workspace

# 带进度汇报（每 60s 通知一次）
$SCRIPTS/claude-spawn.sh research-task "调研XXX行业趋势" ~/.openclaw/workspace \
  --interval 60 --timeout 1200

# 交互式模式（可中途纠偏）
$SCRIPTS/claude-spawn.sh explore-task "探索代码库，找出主要问题" ~/myproject \
  --steerable --interval 120

# 指定模型
$SCRIPTS/claude-spawn.sh heavy-task "复杂分析任务..." . \
  --model claude-opus-4-6 --timeout 1800

# 重试（小八改完 prompt 后）
$SCRIPTS/claude-spawn.sh my-task-retry-1 "改进后的 prompt..." . \
  --parent my-task --retry-count 1
```

**完成后自动通知：** spawn 后在后台启动完成检测器，任务结束时自动调用 `openclaw system event` 通知小八，无需手动轮询。

### claude-check.sh — 查询状态

```bash
claude-check.sh              # 列出所有任务（表格形式）
claude-check.sh <task-id>    # 单任务详情（含结果预览）
```

**确定性检查原则：** 以 tmux session 是否存活为 running 的最终判据，不调用 AI，不消耗 token。

### claude-result.sh — 获取结果

```bash
claude-result.sh <task-id>        # 从 stream-json 提取可读文本
claude-result.sh <task-id> --raw  # 输出原始 stream-json 日志
```

- 任务还在运行时，抓取 tmux 当前屏幕输出
- Print 模式自动解析 stream-json，按优先级提取：result > assistant message > text_delta

### claude-monitor.sh — 批量监控（cron 用）

```bash
claude-monitor.sh    # 检查所有 running 任务，更新状态，通知小八
```

**设置 cron（每 10 分钟）：**
```bash
*/10 * * * * /Users/yjj/.openclaw/workspace/scripts/claude-monitor.sh >> /tmp/clawclau-monitor.log 2>&1
```

作用：作为 spawn 内嵌后台 completion detector 的安全兜底，确保任何情况下任务状态都能被正确更新。

### claude-kill.sh — 终止任务

```bash
claude-kill.sh <task-id>
```

终止 tmux session 并将注册表状态更新为 `killed`。

### claude-steer.sh — 中途纠偏

```bash
claude-steer.sh <task-id> "请聚焦在 X 方面，忽略 Y"
```

通过 `tmux send-keys` 向交互式 Claude 发送纠偏消息。**仅支持 `--steerable` 模式**；print 模式（`claude -p`）非交互，无法 steer。

## 两种运行模式

| 模式 | 命令 | 日志格式 | 支持 steer | 适用场景 |
|------|------|----------|-----------|---------|
| Print（默认）| `claude -p --output-format stream-json` | `.json` | 否 | 任务明确，一次完成 |
| Steerable | `claude --dangerously-skip-permissions` | `.txt` | 是 | 探索性任务，需中途纠正 |

## 重试流程

ClawClau 不自动重试——失败后由小八决策是否重试、如何改进 prompt：

```
任务失败
  → 小八收到 openclaw system event 通知
  → 小八分析失败原因，改进 prompt
  → 小八调用 claude-spawn.sh 派发重试任务（--parent 指向原任务）
  → 注册表记录 parentTaskId + retryCount，最多 maxRetries 次
```

**重试命令示例：**
```bash
# 失败任务: my-task（retry 0）
# 重试 1：改进 prompt 后重新派发
$SCRIPTS/claude-spawn.sh my-task-retry-1 "改进后的 prompt..." . \
  --parent my-task --retry-count 1 --max-retries 3
```

## 任务状态流转

```
running
  → done        (session 结束，日志非空)
  → failed      (session 结束，日志为空)
  → timeout     (超过 --timeout 秒)
  → killed      (手动 claude-kill.sh)
```

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

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CC_HOME` | `~/.clawclau` | 数据目录（注册表、日志、prompts）|

## 设计原则（来自 Elvis 架构）

1. **确定性监控**：tmux 存活 + 日志文件检查，不靠 AI 轮询
2. **隔离执行**：每个任务独立 tmux session，互不干扰
3. **内嵌完成检测**：spawn 时启动后台进程，session 结束即通知
4. **stream-json 日志**：实时写入，可提取中间进度
5. **小八主导重试**：失败通知小八，由小八决策 prompt 如何改进
