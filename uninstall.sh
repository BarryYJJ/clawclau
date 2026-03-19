#!/usr/bin/env bash
# uninstall.sh — ClawClau v2 卸载脚本
#
# 用法: ./uninstall.sh

set -euo pipefail

# ── 颜色 ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "    $*"; }

CC_HOME="$HOME/.clawclau"
DST_SCRIPTS="$HOME/.openclaw/workspace/scripts"
DST_SKILL="$HOME/.openclaw/workspace/skills/clawclau"

CLAWCLAU_SCRIPTS=(
    clawclau-lib.sh
    claude-spawn.sh
    claude-check.sh
    claude-result.sh
    claude-kill.sh
    claude-steer.sh
    claude-monitor.sh
    morning-brief.sh
)

echo ""
echo -e "${BOLD}════════════════════════════════════════════${NC}"
echo -e "${BOLD}  ClawClau v2 卸载程序${NC}"
echo -e "${BOLD}════════════════════════════════════════════${NC}"
echo ""
echo "以下内容将被删除："
echo ""
echo "  1. 数据目录:   $CC_HOME/"
echo "  2. Skill 目录: $DST_SKILL/"
echo "  3. 脚本文件:"
for f in "${CLAWCLAU_SCRIPTS[@]}"; do
    echo "       $DST_SCRIPTS/$f"
done
echo ""
echo -e "${YELLOW}警告：数据目录包含任务日志和注册表，删除后不可恢复。${NC}"
echo ""
read -r -p "确认卸载？（输入 'yes' 继续，其他任意键取消）: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "已取消，未做任何更改。"
    exit 0
fi

echo ""

# 1. 删除数据目录
if [[ -d "$CC_HOME" ]]; then
    rm -rf "$CC_HOME"
    ok "已删除 $CC_HOME/"
else
    info "跳过：$CC_HOME/ 不存在"
fi

# 2. 删除 clawclau 相关脚本
for f in "${CLAWCLAU_SCRIPTS[@]}"; do
    fp="$DST_SCRIPTS/$f"
    if [[ -f "$fp" ]]; then
        rm -f "$fp"
        ok "已删除 $fp"
    else
        info "跳过：$fp 不存在"
    fi
done

# 3. 删除 skill 目录
if [[ -d "$DST_SKILL" ]]; then
    rm -rf "$DST_SKILL"
    ok "已删除 $DST_SKILL/"
else
    info "跳过：$DST_SKILL/ 不存在"
fi

echo ""
echo -e "${GREEN}卸载完成。${NC}"
echo ""
echo "注意事项："
echo "  - crontab 中的 claude-monitor.sh 条目（若有）请手动删除："
echo "    运行 crontab -e，找到并删除包含 claude-monitor.sh 的行"
echo "  - ~/.openclaw/workspace/scripts/ 目录本身未删除（可能有其他脚本）"
echo ""
