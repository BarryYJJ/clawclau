#!/usr/bin/env bash
# install.sh — ClawClau v2 安装脚本
# 支持 macOS 和 Linux
#
# 用法: ./install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"

# ── 颜色 ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }
info() { echo -e "${CYAN}[→]${NC} $*"; }

echo ""
echo -e "${BOLD}════════════════════════════════════════════${NC}"
echo -e "${BOLD}  ClawClau v2 安装程序${NC}"
echo -e "${BOLD}════════════════════════════════════════════${NC}"
echo ""

# ── 1. 检查系统依赖 ────────────────────────────────────────────────────────
echo -e "${BOLD}[1/5] 检查系统依赖...${NC}"
HAS_MISSING=false

# tmux
if command -v tmux >/dev/null 2>&1; then
    ok "tmux $(tmux -V | awk '{print $2}')"
else
    warn "tmux 未安装（必选）"
    if [[ "$OS" == "Darwin" ]]; then
        echo "      安装命令: brew install tmux"
    else
        echo "      安装命令: sudo apt install tmux    # Debian/Ubuntu"
        echo "                sudo yum install tmux    # CentOS/RHEL"
    fi
    HAS_MISSING=true
fi

# jq
if command -v jq >/dev/null 2>&1; then
    ok "jq $(jq --version)"
else
    warn "jq 未安装（必选）"
    if [[ "$OS" == "Darwin" ]]; then
        echo "      安装命令: brew install jq"
    else
        echo "      安装命令: sudo apt install jq      # Debian/Ubuntu"
        echo "                sudo yum install jq      # CentOS/RHEL"
    fi
    HAS_MISSING=true
fi

# claude CLI
if command -v claude >/dev/null 2>&1; then
    ok "claude CLI 已安装"
else
    warn "claude CLI 未安装（必选）"
    echo "      安装命令: npm install -g @anthropic-ai/claude-code"
    echo "      前提:     需要先安装 Node.js >= 18"
    HAS_MISSING=true
fi

if [[ "$HAS_MISSING" == "true" ]]; then
    echo ""
    err "以上必选依赖缺失，请先安装后重新运行 install.sh"
    exit 1
fi

echo ""

# openclaw（可选）
if command -v openclaw >/dev/null 2>&1; then
    ok "openclaw CLI 已安装（cc_notify 通知功能完整可用）"
else
    warn "openclaw CLI 未找到（可选）"
    echo "      cc_notify 将尝试调用 openclaw 发送通知；"
    echo "      未安装时通知会静默失败。可通过配置飞书 webhook 替代。"
fi

# ── 2. 创建数据目录 ────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[2/5] 创建数据目录 ~/.clawclau/...${NC}"
mkdir -p ~/.clawclau/logs ~/.clawclau/prompts ~/.clawclau/backups
[[ -f ~/.clawclau/active-tasks.json ]] || echo '[]' > ~/.clawclau/active-tasks.json
ok "~/.clawclau/{logs,prompts,backups} 已就绪"

# ── 3. 生成默认配置文件 ────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[3/5] 配置文件...${NC}"
if [[ -f ~/.clawclau/config ]]; then
    info "~/.clawclau/config 已存在，跳过（不覆盖）"
else
    cat > ~/.clawclau/config << 'CONFIG_EOF'
# ClawClau 配置文件
#
# 飞书通知目标（群 ID 或机器人 webhook）
# 填写后，cc_notify 会通过 openclaw message send 发送飞书消息。
# 留空则回退到 openclaw system event 通知。
#
# 配置方法：
#   1. 打开飞书，进入目标群 → 群设置 → 群机器人 → 复制群 ID
#   2. 将群 ID 填到下方 notify_chat = 后面（取消注释）
#
# 示例:
#   notify_chat = oc_xxxxxxxxxxxxxxxx
#
notify_chat =
CONFIG_EOF
    ok "~/.clawclau/config 已生成（请编辑配置飞书通知）"
fi

# ── 4. 复制脚本文件 ────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[4/5] 安装脚本文件 → ~/.openclaw/workspace/scripts/...${NC}"
SRC_SCRIPTS="$SCRIPT_DIR/scripts"
DST_SCRIPTS="$HOME/.openclaw/workspace/scripts"

mkdir -p "$DST_SCRIPTS"

COPIED_COUNT=0
SKIPPED_COUNT=0

for f in "$SRC_SCRIPTS"/*.sh; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f")"
    dst="$DST_SCRIPTS/$name"
    if [[ -f "$dst" ]]; then
        info "跳过 $name（已存在）"
        ((SKIPPED_COUNT++)) || true
    else
        cp "$f" "$dst"
        chmod +x "$dst"
        ok "安装 $name"
        ((COPIED_COUNT++)) || true
    fi
done

echo "  共安装 ${COPIED_COUNT} 个脚本，跳过 ${SKIPPED_COUNT} 个（已存在）"

# ── 5. 安装 skill ──────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[5/5] 安装 ClawClau skill...${NC}"
SRC_SKILL="$SCRIPT_DIR/skills/clawclau"
DST_SKILL="$HOME/.openclaw/workspace/skills/clawclau"

if [[ -d "$DST_SKILL" ]]; then
    info "~/.openclaw/workspace/skills/clawclau/ 已存在，跳过"
else
    cp -r "$SRC_SKILL" "$DST_SKILL"
    ok "skills/clawclau/ 已安装"
fi

# ── 安装摘要 ───────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}════════════════════════════════════════════${NC}"
echo -e "${BOLD}  安装完成 — ClawClau v2${NC}"
echo -e "${BOLD}════════════════════════════════════════════${NC}"
echo ""
echo "  数据目录:   ~/.clawclau/"
echo "  脚本目录:   $DST_SCRIPTS/"
echo "  Skill:      $DST_SKILL/"
echo ""
echo -e "${BOLD}接下来需要手动配置：${NC}"
echo ""
echo "  1. 飞书通知（可选）"
echo "     编辑 ~/.clawclau/config，填入 notify_chat 的群 ID"
echo "     不配置时自动使用 openclaw system event 通知"
echo ""
echo "  2. cron 监控守卫（推荐）"
echo "     运行: crontab -e"
echo "     添加: */10 * * * * $DST_SCRIPTS/claude-monitor.sh >> /tmp/clawclau-monitor.log 2>&1"
echo ""
echo "  3. 验证安装"
echo "     $DST_SCRIPTS/claude-check.sh"
echo ""
echo -e "${GREEN}安装成功！${NC}"
echo ""
