#!/usr/bin/env bash
# ============================================================
# morning-brief.sh - 每日早报生成器
# 用法: bash morning-brief.sh
# 依赖: curl, python3 (+ pip install yfinance 可选，用于美股)
#
# 数据来源:
#   美股 (标普/纳斯达克/道琼斯): yfinance 或 Yahoo Finance API
#   A股/港股指数:              腾讯财经 qt.gtimg.cn
#   核心标的:                  腾讯财经 qt.gtimg.cn
#   AI 新闻:                   Hacker News Algolia API (备用: VentureBeat RSS)
# ============================================================

TODAY=$(date "+%Y-%m-%d")
TMPDIR_MB=$(mktemp -d)
trap 'rm -rf "$TMPDIR_MB"' EXIT

# ─────────────────────────────────────────────
# 1. 美股三大指数（隔夜）
# ─────────────────────────────────────────────
cat > "$TMPDIR_MB/us.py" << 'PYEOF'
import sys, json

def fetch_yahoo(ticker, name):
    import urllib.request
    url = "https://query1.finance.yahoo.com/v8/finance/chart/" + ticker + "?interval=1d&range=2d"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=12) as r:
        data = json.loads(r.read())
    closes = data["chart"]["result"][0]["indicators"]["quote"][0]["close"]
    closes = [c for c in closes if c is not None]
    if len(closes) >= 2:
        pct = (closes[-1] - closes[-2]) / closes[-2] * 100
        sign = "+" if pct >= 0 else ""
        return name + ": " + sign + ("%.2f" % pct) + "%"
    return name + ": N/A"

indices = [("^GSPC","标普500"), ("^IXIC","纳斯达克"), ("^DJI","道琼斯")]
results = []

try:
    import yfinance as yf
    for sym, name in indices:
        try:
            t = yf.Ticker(sym)
            hist = t.history(period="2d")
            if len(hist) >= 2:
                prev, curr = float(hist["Close"].iloc[-2]), float(hist["Close"].iloc[-1])
                pct = (curr - prev) / prev * 100
                sign = "+" if pct >= 0 else ""
                results.append(name + ": " + sign + ("%.2f" % pct) + "%")
            else:
                results.append(fetch_yahoo(sym, name))
        except Exception:
            results.append(fetch_yahoo(sym, name))
except ImportError:
    for sym, name in indices:
        try:
            results.append(fetch_yahoo(sym, name))
        except Exception:
            results.append(name + ": 获取失败")

print(" | ".join(results))
PYEOF

printf "📊 每日早报 | %s\n\n" "$TODAY"
printf "📈 隔夜外盘\n"
US_RESULT=$(python3 "$TMPDIR_MB/us.py" 2>/dev/null)
printf "%s\n" "${US_RESULT:-标普500: 获取失败 | 纳斯达克: 获取失败 | 道琼斯: 获取失败}"

# ─────────────────────────────────────────────
# 2. A股指数
# ─────────────────────────────────────────────
cat > "$TMPDIR_MB/cn.py" << 'PYEOF'
import urllib.request, re

codes = [("sh000001", "上证"), ("sz399001", "深证")]
url = "https://qt.gtimg.cn/q=" + ",".join(c for c, _ in codes)
try:
    req = urllib.request.Request(url, headers={
        "Referer": "https://finance.qq.com",
        "User-Agent": "Mozilla/5.0"
    })
    with urllib.request.urlopen(req, timeout=10) as r:
        text = r.read().decode("gbk", errors="ignore")
    results = []
    for code, name in codes:
        m = re.search("v_" + code + '="([^"]+)"', text)
        if m:
            f = m.group(1).split("~")
            try:
                price = float(f[3])
                pct   = float(f[32])
                sign  = "+" if pct >= 0 else ""
                results.append(name + ": " + ("%.2f" % price) + " (" + sign + ("%.2f" % pct) + "%)")
            except Exception:
                results.append(name + ": 解析失败")
        else:
            results.append(name + ": 数据缺失")
    print(" | ".join(results))
except Exception as e:
    print("获取失败: " + str(e))
PYEOF

printf "\n🇨🇳 A股（最新收盘）\n"
CN_RESULT=$(python3 "$TMPDIR_MB/cn.py" 2>/dev/null)
printf "%s\n" "${CN_RESULT:-A股数据获取失败}"

# ─────────────────────────────────────────────
# 3. 港股恒生指数
# ─────────────────────────────────────────────
cat > "$TMPDIR_MB/hk.py" << 'PYEOF'
import urllib.request, re

url = "https://qt.gtimg.cn/q=r_hkHSI"
try:
    req = urllib.request.Request(url, headers={
        "Referer": "https://finance.qq.com",
        "User-Agent": "Mozilla/5.0"
    })
    with urllib.request.urlopen(req, timeout=10) as r:
        text = r.read().decode("gbk", errors="ignore")
    m = re.search('v_r_hkHSI="([^"]+)"', text)
    if m:
        f = m.group(1).split("~")
        price = float(f[3])
        pct   = float(f[32])
        sign  = "+" if pct >= 0 else ""
        print("恒生: " + ("%.2f" % price) + " (" + sign + ("%.2f" % pct) + "%)")
    else:
        print("恒生: 数据缺失")
except Exception as e:
    print("恒生: 获取失败 (" + str(e) + ")")
PYEOF

printf "\n🇭🇰 港股（最新收盘）\n"
HK_RESULT=$(python3 "$TMPDIR_MB/hk.py" 2>/dev/null)
printf "%s\n" "${HK_RESULT:-港股数据获取失败}"

# ─────────────────────────────────────────────
# 4. 核心标的涨跌
# ─────────────────────────────────────────────

# 默认标的列表（可被 ~/Desktop/stock_watchlist_data.py 覆盖/扩充）
DEFAULT_STOCKS="sh600519,sz000858,sz300750,sh601012,sz002594,sh601318,sh600036,sz002415,sh600276,sz300059,hk00700,hk09988,hk03690,hk09618"

EXTRA_STOCKS=""
WATCHLIST_FILE="$HOME/Desktop/stock_watchlist_data.py"
if [[ -f "$WATCHLIST_FILE" ]]; then
    cat > "$TMPDIR_MB/parse_watchlist.py" << 'PYEOF'
import sys, re
with open(sys.argv[1]) as f:
    content = f.read()
codes = re.findall('["\']([shz]{2}[0-9]{6}|hk[0-9]{5})["\']', content)
if codes:
    print(",".join(dict.fromkeys(codes)))
PYEOF
    EXTRA_STOCKS=$(python3 "$TMPDIR_MB/parse_watchlist.py" "$WATCHLIST_FILE" 2>/dev/null)
fi

ALL_STOCKS="${DEFAULT_STOCKS}${EXTRA_STOCKS:+,$EXTRA_STOCKS}"

cat > "$TMPDIR_MB/stocks.py" << 'PYEOF'
import urllib.request, re, sys, json

stocks = list(dict.fromkeys(s.strip() for s in sys.argv[1].split(",") if s.strip()))
cn_hk  = [s for s in stocks if not s.startswith("us.")]

results = []

BATCH = 40
for i in range(0, len(cn_hk), BATCH):
    batch = cn_hk[i:i+BATCH]
    url = "https://qt.gtimg.cn/q=" + ",".join(batch)
    try:
        req = urllib.request.Request(url, headers={
            "Referer": "https://finance.qq.com",
            "User-Agent": "Mozilla/5.0"
        })
        with urllib.request.urlopen(req, timeout=15) as r:
            text = r.read().decode("gbk", errors="ignore")
        for code in batch:
            m = re.search("v_" + re.escape(code) + '="([^"]+)"', text)
            if m:
                f = m.group(1).split("~")
                try:
                    name  = f[1]
                    price = float(f[3])
                    pct   = float(f[32])
                    results.append((name, price, pct))
                except Exception:
                    pass
    except Exception:
        pass

if not results:
    print("FAIL")
    sys.exit(0)

results.sort(key=lambda x: x[2], reverse=True)
top5 = results[:5]
bot5 = results[-5:]

def fmt(items):
    parts = []
    for n, v, p in items:
        sign = "+" if p >= 0 else ""
        parts.append(n + " " + sign + ("%.2f" % p) + "%")
    return ", ".join(parts)

print("TOP:" + fmt(top5))
print("BOT:" + fmt(bot5))
PYEOF

printf "\n🔍 核心标的涨跌（Top 5 涨 / Top 5 跌）\n"
STOCK_RESULT=$(python3 "$TMPDIR_MB/stocks.py" "$ALL_STOCKS" 2>/dev/null)
if [[ -z "$STOCK_RESULT" || "$STOCK_RESULT" == "FAIL" ]]; then
    printf "标的数据获取失败\n"
else
    TOP_LINE=$(printf "%s" "$STOCK_RESULT" | grep "^TOP:" | sed 's/^TOP://')
    BOT_LINE=$(printf "%s" "$STOCK_RESULT" | grep "^BOT:" | sed 's/^BOT://')
    printf "涨幅榜: %s\n" "$TOP_LINE"
    printf "跌幅榜: %s\n" "$BOT_LINE"
fi

# ─────────────────────────────────────────────
# 5. AI 要闻
# ─────────────────────────────────────────────
cat > "$TMPDIR_MB/news.py" << 'PYEOF'
import urllib.request, json, time

cutoff = int(time.time()) - 86400
url = (
    "https://hn.algolia.com/api/v1/search"
    "?query=AI+LLM+GPT+artificial+intelligence"
    "&tags=story"
    "&numericFilters=created_at_i>" + str(cutoff) +
    "&hitsPerPage=10"
)

try:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=12) as r:
        data = json.loads(r.read())
    hits = data.get("hits", [])
    seen, news = set(), []
    for h in hits:
        title = (h.get("title") or "").strip()
        raw_url = h.get("url") or ""
        src = raw_url.split("/")[2].replace("www.", "") if raw_url else "Hacker News"
        if title and title not in seen and len(news) < 5:
            seen.add(title)
            news.append((title, src))
    if news:
        for i, (t, s) in enumerate(news, 1):
            print(str(i) + ". " + t + " - " + s)
    else:
        raise ValueError("empty results")
except Exception:
    try:
        import xml.etree.ElementTree as ET
        rss_url = "https://venturebeat.com/category/ai/feed/"
        req = urllib.request.Request(rss_url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=12) as r:
            root = ET.fromstring(r.read())
        items = root.findall(".//item")[:5]
        for i, item in enumerate(items, 1):
            title = (item.findtext("title") or "").strip()
            link  = item.findtext("link") or ""
            src   = link.split("/")[2].replace("www.", "") if link else "VentureBeat"
            print(str(i) + ". " + title + " - " + src)
    except Exception as e:
        print("1. AI 新闻获取失败 (" + str(e) + ")")
PYEOF

printf "\n📰 AI 要闻\n"
NEWS_RESULT=$(python3 "$TMPDIR_MB/news.py" 2>/dev/null)
printf "%s\n" "${NEWS_RESULT:-1. AI 新闻获取失败，请手动查看}"

printf "\n%s\n" "--------------------------------------"
printf "生成时间: %s | 数据仅供参考，不构成投资建议\n" "$(date '+%H:%M:%S')"
