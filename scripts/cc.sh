#!/usr/bin/env bash
# IP 判官 · Claude Code / Codex 终端出口体检    https://ipjudge.org/claude-code/
#   curl -sL ipjudge.org/cc | bash            中文
#   curl -sL ipjudge.org/en/cc | bash         English
# 为什么要单独测终端:Claude Code、Codex 跑在终端里,只认 HTTPS_PROXY 这类环境变量,不一定走浏览器用的代理。
# 只读检查:不安装任何东西、不改任何设置、不上传任何数据(只向 ipjudge.org 查询出口 IP 的判定)。

LANG_EN=0
for a in "$@"; do case "$a" in --en|-e|en) LANG_EN=1 ;; esac; done
[ "${IPJUDGE_LANG:-}" = "en" ] && LANG_EN=1
T() { if [ "$LANG_EN" = 1 ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }

if [ -t 1 ]; then B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; D=$'\e[2m'; N=$'\e[0m'; else B=; G=; Y=; R=; D=; N=; fi
SITE="${IPJUDGE_SITE:-https://ipjudge.org}"
Q=""; [ "$LANG_EN" = 1 ] && Q="/en"
command -v curl >/dev/null 2>&1 || { echo "$(T '需要 curl' 'curl is required')"; exit 1; }

head_() { printf '\n%s== %s ==%s\n' "$B" "$1" "$N"; }
row()   { local b a n w; b=$(printf '%s' "$1" | LC_ALL=C wc -c); a=$(printf '%s' "$1" | LC_ALL=C tr -cd '\000-\177' | LC_ALL=C wc -c)
          n=$(( (b - a) / 3 )); w=$(( a + n * 2 )); printf '  %s%*s %s\n' "$1" $(( w < 20 ? 20 - w : 1 )) '' "$2"; }
ok()   { printf '%s%s%s' "$G" "$1" "$N"; }
warn() { printf '%s%s%s' "$Y" "$1" "$N"; }
bad()  { printf '%s%s%s' "$R" "$1" "$N"; }
dim()  { printf '%s%s%s' "$D" "$1" "$N"; }
NB=0; NW=0; FIX=""
issue() { if [ "$1" = bad ]; then NB=$((NB+1)); else NW=$((NW+1)); fi; FIX="$FIX\n  $([ "$1" = bad ] && bad '✕' || warn '!') $2\n    $(dim "$3")"; }
# 隐去代理地址里的用户名密码
mask() { printf '%s' "$1" | sed -E 's#(://)[^/@]+@#\1***@#'; }
# trace <host> [extra curl args]  → "ip loc"(按当前环境变量走代理,和 Claude Code / Codex 一样)
trace() { local h="$1"; shift; curl -sS --max-time 10 "$@" "https://$h/cdn-cgi/trace" 2>/dev/null | awk -F= '/^ip=/{i=$2}/^loc=/{l=$2}END{if(i)print i" "l}'; }
LIMITED=" CN HK MO "

printf '%sIP 判官 · %s%s  %s\n' "$B" "$(T 'Claude Code / Codex 终端出口体检' 'Claude Code / Codex terminal exit check')" "$N" "$(dim "$SITE")"
printf '%s\n' "$(dim "$(T '只读检查，不安装、不修改、不上传。约 20 秒。' 'Read-only: installs, changes and uploads nothing. About 20 seconds.')")"

# ---------- 1. 代理环境变量 ----------
head_ "$(T '终端的代理设置' 'Proxy settings in this terminal')"
HAS_ENV=0
for v in HTTPS_PROXY https_proxy HTTP_PROXY http_proxy ALL_PROXY all_proxy NO_PROXY no_proxy; do
  val="${!v:-}"; [ -n "$val" ] || continue
  row "$v" "$(mask "$val")"; case "$v" in NO_PROXY|no_proxy) ;; *) HAS_ENV=1 ;; esac
done
[ "$HAS_ENV" = 1 ] || row "HTTPS_PROXY" "$(warn "$(T '没有设置' 'not set')")"
# Claude Code 自己的规则(官方文档 code.claude.com/docs/en/corporate-proxy):
#   只认 https_proxy → HTTPS_PROXY → http_proxy → HTTP_PROXY 第一个有值的;也读 ~/.claude/settings.json 的 env;
#   不支持 SOCKS,也不读 ALL_PROXY。curl 却会读 ALL_PROXY —— 所以要按 Claude Code 的规则单独算,唔可以直接信 curl。
CCP=""; CCSRC=""
for v in https_proxy HTTPS_PROXY http_proxy HTTP_PROXY; do val="${!v:-}"; if [ -n "$val" ]; then CCP="$val"; CCSRC="$v"; break; fi; done
CSET="$HOME/.claude/settings.json"
if [ -z "$CCP" ] && [ -f "$CSET" ] && command -v python3 >/dev/null 2>&1; then
  CCP=$(python3 -c 'import json,sys
try: e=(json.load(open(sys.argv[1])).get("env") or {})
except Exception: e={}
print(next((e[k] for k in ("https_proxy","HTTPS_PROXY","http_proxy","HTTP_PROXY") if e.get(k)),""))' "$CSET" 2>/dev/null)
  [ -n "$CCP" ] && CCSRC="~/.claude/settings.json"
fi
row "$(T 'Claude Code 实际用的代理' 'Proxy Claude Code uses')" "$( [ -n "$CCP" ] && printf '%s  %s' "$(mask "$CCP")" "$(dim "($CCSRC)")" || warn "$(T '无（直连）' 'none (direct)')")"
case "$CCP" in socks*)
  issue bad "$(T 'Claude Code 不支持 SOCKS 代理' 'Claude Code does not support SOCKS proxies')" "$(T '把代理地址换成代理软件的 HTTP / 混合端口，例如 http://127.0.0.1:7890。' 'Use your proxy app’s HTTP / mixed port instead, e.g. http://127.0.0.1:7890.')" ;;
esac
if [ -z "$CCP" ] && { [ -n "${ALL_PROXY:-}" ] || [ -n "${all_proxy:-}" ]; }; then
  issue bad "$(T '只设了 ALL_PROXY：curl 会走代理，Claude Code 不会' 'Only ALL_PROXY is set: curl uses it, Claude Code does not')" \
    "$(T 'Claude Code 不读 ALL_PROXY。再加一行 export https_proxy=http://127.0.0.1:端口（HTTP / 混合端口）。' 'Claude Code ignores ALL_PROXY. Also export https_proxy=http://127.0.0.1:PORT (HTTP / mixed port).')"
fi
SYS=""
if command -v scutil >/dev/null 2>&1; then
  P=$(scutil --proxy 2>/dev/null)
  if printf '%s' "$P" | grep -q 'HTTPSEnable : 1'; then SYS="$(printf '%s' "$P" | awk '/HTTPSProxy :/{h=$3}/HTTPSPort :/{p=$3}END{print h":"p}')"; fi
  row "$(T 'macOS 系统代理' 'macOS system proxy')" "${SYS:-$(dim "$(T '未开启' 'off')")}"
fi

# ---------- 2. 各服务看到的出口(和 Claude Code / Codex 走同一条路) ----------
head_ "$(T '终端访问 AI 服务的出口' 'Exits your terminal uses for AI services')"
SEEN=" "; NSEEN=0
MAINIP=""; MAINCC=""; UNREACH=""
for pair in "Claude Code:api.anthropic.com" "claude.ai:claude.ai" "Codex / OpenAI API:api.openai.com" "ChatGPT:chatgpt.com"; do
  name="${pair%%:*}"; host="${pair#*:}"
  if [ "$host" = api.anthropic.com ]; then
    case "$CCP" in socks*) r="" ;; "") r=$(trace "$host" --noproxy '*') ;; *) r=$(trace "$host" -x "$CCP") ;; esac
  else r=$(trace "$host"); fi
  if [ -z "$r" ]; then row "$name" "$(bad "$(T "连不上 $host" "cannot reach $host")")"; UNREACH="$UNREACH $host"; continue; fi
  ip="${r%% *}"; cc="${r#* }"; case "$SEEN" in *" $ip "*) ;; *) SEEN="$SEEN$ip "; NSEEN=$((NSEEN+1)) ;; esac
  [ -n "$MAINIP" ] || { MAINIP="$ip"; MAINCC="$cc"; }
  if [[ "$LIMITED" == *" $cc "* ]]; then
    row "$name" "$ip · $cc  $(bad "$(T '✕ 地区不支持' '✕ region not supported')")"
    issue bad "$(T "$name 走的出口在 ${cc}（${ip}），该地区不被支持" "$name exits in $cc ($ip), which is not supported")" \
      "$(T '终端很可能在直连。给终端设置代理（HTTPS_PROXY），或把代理切到 TUN / 增强模式。' 'The terminal is probably going direct. Set HTTPS_PROXY for the terminal, or switch the proxy to TUN / enhanced mode.')"
  else row "$name" "$ip · $cc  $(ok '✓')"; fi
done
if [ -n "$UNREACH" ]; then
  issue bad "$(T "终端连不上:$UNREACH" "The terminal cannot reach:$UNREACH")" \
    "$(T '检查代理软件是否在运行；设置了 HTTPS_PROXY 的，确认端口和代理软件里的一致（常见 7890、7897）。' 'Check the proxy app is running; if HTTPS_PROXY is set, make sure its port matches the proxy app (often 7890 or 7897).')"
fi
if [ "$NSEEN" -gt 1 ]; then
  printf '  %s\n' "$(warn "$(T "这几个服务走了 $NSEEN 个不同的出口（按域名分流）" "These services use $NSEEN different exits (split by domain)")")"
  issue warn "$(T '终端访问 Anthropic / OpenAI 的出口不一致' 'The terminal reaches Anthropic / OpenAI through different exits')" \
    "$(T '同一个账号在不同出口之间切换，容易触发验证。把 anthropic.com、claude.ai、openai.com、chatgpt.com 放进同一条线路。' 'Switching one account between exits invites verification. Put anthropic.com, claude.ai, openai.com and chatgpt.com on the same line.')"
fi

# ---------- 3. 出口 IP 的类型(IP 判官判定) ----------
if [ -n "$MAINIP" ]; then
  head_ "$(T "Claude Code 出口 $MAINIP 的判定" "Verdict for the Claude Code exit $MAINIP")"
  REP=$(curl -sS --max-time 15 -A "curl/ipjudge-cc" "$SITE$Q/ip/$MAINIP" 2>/dev/null)
  if printf '%s' "$REP" | grep -q '^IP'; then printf '%s\n' "$REP" | sed 's/^/  /'
    if printf '%s' "$REP" | grep -Eq '机房 IP|Datacenter IP'; then issue warn "$(T '出口是机房 IP' 'The exit is a datacenter IP')" "$(T 'Anthropic、OpenAI 对机房 IP 的验证和风控更频繁，住宅线路通常更稳。' 'Anthropic and OpenAI challenge datacenter IPs more often; a residential line is usually steadier.')"; fi
    if printf '%s' "$REP" | grep -Eq '代理 / VPN|Proxy / VPN'; then issue bad "$(T '出口被识别为代理 / VPN' 'The exit is flagged as proxy / VPN')" "$(T '换一条没有被标记的线路。' 'Use a line that is not flagged.')"; fi
  else row "$(T '判定' 'Verdict')" "$(dim "$(T "这次没查到，可以打开 $SITE$Q/ip/$MAINIP 看" "lookup failed; open $SITE$Q/ip/$MAINIP instead")")"; fi
fi

# ---------- 4. 直连对照:不走代理时是哪个 IP ----------
head_ "$(T '对照：不走代理时的出口' 'For comparison: the exit without any proxy')"
DIRECT=$(trace api.anthropic.com --noproxy '*')
if [ -n "$DIRECT" ]; then
  dip="${DIRECT%% *}"; dcc="${DIRECT#* }"; row "$(T '直连出口' 'Direct exit')" "$dip · $dcc"
  if [ -n "$MAINIP" ] && [ "$dip" = "$MAINIP" ] && [ -z "$CCP" ]; then
    if [ -n "$SYS" ]; then
      issue bad "$(T '系统代理开着，但终端没有用上它' 'The system proxy is on, but the terminal is not using it')" \
        "$(T "终端默认不读 macOS 系统代理。在 ~/.zshrc 里加：export https_proxy=http://${SYS} http_proxy=http://${SYS} ，或开 TUN 模式。（Claude Code 不支持 SOCKS，要用 HTTP 端口）" "Terminals ignore the macOS system proxy. Add to ~/.zshrc: export https_proxy=http://${SYS} http_proxy=http://${SYS} , or use TUN mode. (Claude Code doesn’t support SOCKS — use the HTTP port.)")"
    else printf '  %s\n' "$(dim "$(T '和上面相同：终端要么在直连，要么由 TUN / 路由器透明代理接管' 'Same as above: the terminal either goes direct or is handled by TUN / a router-level proxy')")"; fi
  fi
else row "$(T '直连出口' 'Direct exit')" "$(dim "$(T '直连连不上（正常：说明必须经代理）' 'unreachable directly (fine: traffic must use the proxy)')")"; fi

# ---------- 5. IPv6 ----------
V6=$(trace api.anthropic.com -6)
case "${V6%% *}" in *:*) ;; *) V6="" ;; esac   # 走 TUN 时 -6 可能拿到 IPv4 出口,唔当 IPv6
if [ -n "$V6" ]; then
  head_ "IPv6"; v6ip="${V6%% *}"; v6cc="${V6#* }"; row "api.anthropic.com (IPv6)" "$v6ip · $v6cc"
  if [ -n "$MAINCC" ] && [ "$v6cc" != "$MAINCC" ]; then issue warn "$(T "IPv6 出口在 ${v6cc}，和 IPv4（${MAINCC}）不同" "The IPv6 exit is in $v6cc, not $MAINCC like IPv4")" "$(T '优先用 IPv6 时会从另一个地区出去。让代理接管 IPv6，或在系统里关闭 IPv6。' 'When IPv6 is preferred you leave from another region. Let the proxy handle IPv6, or turn IPv6 off.')"; fi
fi

# ---------- 6. 时区 ----------
head_ "$(T '终端时区' 'Terminal time zone')"
TZN="${TZ:-}"; [ -z "$TZN" ] && [ -L /etc/localtime ] && TZN=$(readlink /etc/localtime | sed 's#.*/zoneinfo/##')
row "TZ" "${TZN:-$(date +%Z)}"
case "$TZN" in Asia/Shanghai|Asia/Chongqing|Asia/Hong_Kong|Asia/Macau|PRC)
  if [ -n "$MAINCC" ] && [[ "$LIMITED" != *" $MAINCC "* ]]; then printf '  %s\n' "$(dim "$(T "时区在中国，出口在 ${MAINCC}：一般不影响，想更一致可以在启动前 export TZ=America/Los_Angeles" "Time zone is in China, exit is in $MAINCC: usually harmless; for consistency, export TZ=America/Los_Angeles before starting")")"; fi ;;
esac

# ---------- 结论 ----------
head_ "$(T '结论' 'Result')"
if [ "$NB" = 0 ] && [ "$NW" = 0 ]; then printf '  %s\n' "$(ok "$(T '没有发现问题：终端访问 AI 服务的出口一致、地区受支持。' 'No problems: the terminal reaches AI services through one supported exit.')")"
else printf '  %s\n' "$(T "有 ${NB} 项要处理、${NW} 项建议留意：" "${NB} to fix, ${NW} to watch:")"; printf '%b\n' "$FIX"; fi
printf '\n  %s\n' "$(dim "$(T "浏览器那边也要测：打开 $SITE 对照「访问 Claude 的 IP」是不是同一个。" "Check the browser too: open $SITE and compare its \"IP used for Claude\".")")"
