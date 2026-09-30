#!/usr/bin/env bash
# IP 判官 · 服务器一键体检    https://ipjudge.org/cli/
#   bash <(curl -Ls ipjudge.org/sh)            中文
#   bash <(curl -Ls ipjudge.org/sh) --en       English
# 只读检查:不安装任何东西、不改系统设置、不上传任何数据。
# 除了向 ipjudge.org 查询本机出口(和直接 curl ipjudge.org 一样),其余请求都是直接访问各平台的公开页面。

LANG_EN=0
for a in "$@"; do case "$a" in --en|-e|en) LANG_EN=1 ;; esac; done
[ "${IPJUDGE_LANG:-}" = "en" ] && LANG_EN=1

T() { if [ "$LANG_EN" = 1 ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }

if [ -t 1 ]; then B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; D=$'\e[2m'; N=$'\e[0m'; else B=; G=; Y=; R=; D=; N=; fi
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
SITE="${IPJUDGE_SITE:-https://ipjudge.org}"
Q=""; [ "$LANG_EN" = 1 ] && Q="en/"

command -v curl >/dev/null 2>&1 || { echo "$(T '需要 curl' 'curl is required')"; exit 1; }

head_() { printf '\n%s== %s ==%s\n' "$B" "$1" "$N"; }
# 标签按显示宽度对齐(中文占 2 格;唔依赖系统 locale)
row()   { local b a n w; b=$(printf '%s' "$1" | LC_ALL=C wc -c); a=$(printf '%s' "$1" | LC_ALL=C tr -cd '\000-\177' | LC_ALL=C wc -c)
          n=$(( (b - a) / 3 )); w=$(( a + n * 2 )); printf '  %s%*s %s\n' "$1" $(( w < 18 ? 18 - w : 1 )) '' "$2"; }
ok()    { printf '%s%s%s' "$G" "$1" "$N"; }
warn()  { printf '%s%s%s' "$Y" "$1" "$N"; }
bad()   { printf '%s%s%s' "$R" "$1" "$N"; }
dim()   { printf '%s%s%s' "$D" "$1" "$N"; }

# curl 包装:$1=4|6|any  其余参数原样传给 curl
c() { local v="$1"; shift; case "$v" in 4) curl -4 -sS --max-time 10 "$@" 2>/dev/null ;; 6) curl -6 -sS --max-time 10 "$@" 2>/dev/null ;; *) curl -sS --max-time 10 "$@" 2>/dev/null ;; esac; }
trace_loc() { c "$1" "https://$2/cdn-cgi/trace" | sed -n 's/^loc=//p'; }
trace_ip()  { c "$1" "https://$2/cdn-cgi/trace" | sed -n 's/^ip=//p'; }

printf '%sIP 判官 · %s%s  %s\n' "$B" "$(T '服务器体检' 'server check')" "$N" "$(dim "$SITE")"
printf '%s\n' "$(dim "$(T '只读检查,不安装、不修改、不上传。约 30 秒。' 'Read-only: installs, changes and uploads nothing. About 30 seconds.')")"

# ---------- 1. 出口 IP 判定(ipjudge.org 的文字报告) ----------
HAS4=0; HAS6=0
R4=$(c 4 -A "curl/ipjudge-sh" "$SITE/$Q")
if [ -n "$R4" ] && printf '%s' "$R4" | grep -q '^IP'; then HAS4=1; fi
R6=$(c 6 -A "curl/ipjudge-sh" "$SITE/$Q")
if [ -n "$R6" ] && printf '%s' "$R6" | grep -q '^IP'; then HAS6=1; fi

head_ "$(T '出口 IPv4' 'IPv4 exit')"
if [ "$HAS4" = 1 ]; then printf '%s\n' "$R4" | sed 's/^/  /'; else row "IPv4" "$(bad "$(T '没有 IPv4 出口,或连不上 ipjudge.org' 'no IPv4 exit, or ipjudge.org unreachable')")"; fi
head_ "$(T '出口 IPv6' 'IPv6 exit')"
if [ "$HAS6" = 1 ]; then printf '%s\n' "$R6" | sed 's/^/  /'; else row "IPv6" "$(dim "$(T '没有 IPv6 出口' 'no IPv6 exit')")"; fi

CC4=$(trace_loc 4 www.cloudflare.com)
CC6=""; [ "$HAS6" = 1 ] && CC6=$(trace_loc 6 www.cloudflare.com)
if [ -n "$CC4" ] && [ -n "$CC6" ] && [ "$CC4" != "$CC6" ]; then
  printf '  %s\n' "$(warn "$(T "IPv4 定位在 $CC4、IPv6 定位在 $CC6:优先走 IPv6 的网站会看到另一个地区" "IPv4 geolocates to $CC4 and IPv6 to $CC6: sites that prefer IPv6 see a different region")")"
fi

# ---------- 2. AI 平台 ----------
# 三家官方可用地区由 ipjudge.org 按官方名单回答(纯文本:chatgpt claude gemini,1=可用 0=不可用)
ai_ok() { c any "$SITE/api/ai/$1" ; }
head_ "$(T 'AI 平台(本机直接访问)' 'AI platforms (reached from this server)')"
for pair in "ChatGPT:chatgpt.com" "Claude:claude.ai"; do
  name=${pair%%:*}; host=${pair#*:}
  loc=$(trace_loc any "$host"); ip=$(trace_ip any "$host")
  if [ -z "$loc" ]; then row "$name" "$(bad "$(T "连不上 $host" "cannot reach $host")")"; continue; fi
  flags=$(ai_ok "$loc"); [ "$name" = ChatGPT ] && f=$(echo "$flags" | awk '{print $1}') || f=$(echo "$flags" | awk '{print $2}')
  if [ "$f" = 1 ]; then st=$(ok "$(T '地区支持' 'region supported')"); elif [ "$f" = 0 ]; then st=$(bad "$(T '地区不支持' 'region not supported')"); else st=$(dim '?'); fi
  row "$name" "$ip · $loc · $st"
done
# OpenAI API:不带 key 访问,被地区拦截时返回 unsupported_country_region_territory
oa=$(c any https://api.openai.com/v1/models)
if printf '%s' "$oa" | grep -q 'unsupported_country'; then row "OpenAI API" "$(bad "$(T '地区被拦截(unsupported_country_region_territory)' 'blocked by region (unsupported_country_region_territory)')")"
elif printf '%s' "$oa" | grep -qi 'api key\|invalid_api_key\|authentication'; then row "OpenAI API" "$(ok "$(T '可访问(只差 API key)' 'reachable (only the API key is missing)')")"
else row "OpenAI API" "$(dim "$(T '没有得到预期回应' 'unexpected response')")"; fi
an=$(c any -o /dev/null -w '%{http_code}' https://api.anthropic.com/v1/models)
case "$an" in 401) row "Anthropic API" "$(ok "$(T '可访问(只差 API key)' 'reachable (only the API key is missing)')")" ;;
  403) row "Anthropic API" "$(bad "$(T '403 拒绝访问(常见于不支持的地区)' '403 forbidden (common in unsupported regions)')")" ;;
  ""|000) row "Anthropic API" "$(bad "$(T '连不上' 'unreachable')")" ;;
  *) row "Anthropic API" "$(dim "HTTP $an")" ;; esac
if [ -n "$CC4" ]; then g=$(ai_ok "$CC4" | awk '{print $3}')
  [ "$g" = 1 ] && row "Gemini" "$(ok "$(T "按出口地区 $CC4:支持" "by exit region $CC4: supported")")" || row "Gemini" "$(bad "$(T "按出口地区 $CC4:不支持" "by exit region $CC4: not supported")")"; fi

# ---------- 3. 常用平台 ----------
head_ "$(T '常用平台(参考)' 'Other platforms (for reference)')"
# Netflix:按片子能否打开判断片库(会先 301 到地区路径,要跟随跳转)
nf1=$(c any -L -o /dev/null -w '%{http_code}' -A "$UA" https://www.netflix.com/title/81280792)   # 自制剧
nf2=$(c any -L -o /dev/null -w '%{http_code}' -A "$UA" https://www.netflix.com/title/70143836)   # 非自制剧
nfr=$(c any -L -o /dev/null -w '%{url_effective}' -A "$UA" https://www.netflix.com/title/80018499 | sed -n 's#.*netflix.com/\([a-z][a-z]\)\(-[a-z][a-z]\)\{0,1\}/title.*#\1#p' | tr a-z A-Z)
if [ "$nf2" = 200 ]; then row "Netflix" "$(ok "$(T '完整片库' 'full catalog')")${nfr:+ · $nfr}"
elif [ "$nf1" = 200 ]; then row "Netflix" "$(warn "$(T '只能看自制剧' 'Netflix originals only')")${nfr:+ · $nfr}"
elif [ "$nf1" = 403 ] || [ "$nf1" = 404 ]; then row "Netflix" "$(bad "$(T '不可用' 'not available')")"
else row "Netflix" "$(dim "$(T '检测失败' 'check failed') ($nf1)")"; fi
yt=$(c any -A "$UA" -H 'Accept-Language: en' https://www.youtube.com/premium)
ytr=$(printf '%s' "$yt" | grep -o '"INNERTUBE_CONTEXT_GL":"[A-Z]*"' | head -1 | sed 's/.*:"\(.*\)"/\1/')
if [ -z "$yt" ]; then row "YouTube Premium" "$(bad "$(T '连不上' 'unreachable')")"
elif printf '%s' "$yt" | grep -q 'Premium is not available in your country'; then row "YouTube Premium" "$(bad "$(T '该地区不可用' 'not available here')")${ytr:+ · $ytr}"
else row "YouTube Premium" "$(ok "$(T '可用' 'available')")${ytr:+ · $ytr}"; fi
tt=$(c any -A "$UA" https://www.tiktok.com/explore | grep -o '"region":"[A-Z]*"' | head -1 | sed 's/.*:"\(.*\)"/\1/')
if [ -n "$tt" ]; then
  case "$tt" in CN|HK|IN) row "TikTok" "$(bad "$(T "地区 $tt:TikTok 不在该地区提供服务" "region $tt: TikTok is not offered there")")" ;; *) row "TikTok" "$(ok "$(T "地区 $tt" "region $tt")")" ;; esac
else row "TikTok" "$(dim "$(T '读不到地区(可能打不开,或不在服务地区)' 'region not detected (blocked, or not offered here)')")"; fi

# ---------- 4. DNS ----------
head_ "DNS"
ns=$(grep -E '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ' ')
row "$(T '系统解析器' 'Resolvers')" "${ns:-$(dim '?')}"
if command -v dig >/dev/null 2>&1; then
  eg=$(dig +short +time=3 +tries=1 TXT o-o.myaddr.l.google.com 2>/dev/null | tr -d '"' | grep -v '^edns' | head -1)
  row "$(T '解析出口' 'Resolver egress')" "${eg:-$(dim '?')} $(dim "$(T '(Google 看到的解析器出口 IP)' '(resolver IP as seen by Google)')")"
elif command -v nslookup >/dev/null 2>&1; then
  eg=$(nslookup -type=TXT o-o.myaddr.l.google.com 2>/dev/null | grep -o '"[0-9a-f.:]*"' | head -1 | tr -d '"')
  row "$(T '解析出口' 'Resolver egress')" "${eg:-$(dim '?')}"
else row "$(T '解析出口' 'Resolver egress')" "$(dim "$(T '没有 dig / nslookup,跳过' 'no dig / nslookup, skipped')")"; fi

# ---------- 5. 本机 ----------
head_ "$(T '本机' 'This server')"
os=$( (. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") || uname -s)
row "$(T '系统' 'OS')" "$os · $(uname -r)"
vt=$(command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt 2>/dev/null)
row "$(T '虚拟化' 'Virtualization')" "${vt:-$(dim '?')}"
cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
qd=$(sysctl -n net.core.default_qdisc 2>/dev/null)
if [ "$cc" = bbr ]; then row "$(T '拥塞控制' 'Congestion control')" "$(ok bbr)${qd:+ · $qd}"; else row "$(T '拥塞控制' 'Congestion control')" "$(warn "${cc:-?}")${qd:+ · $qd} $(dim "$(T '(没开 BBR,长距离传输会慢)' '(BBR off: long-distance transfers are slower)')")"; fi
tz=$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || date +%Z)
row "$(T '时区' 'Time zone')" "${tz:-?}"
if command -v timeout >/dev/null 2>&1; then
  if timeout 5 bash -c 'exec 3<>/dev/tcp/gmail-smtp-in.l.google.com/25' 2>/dev/null; then row "$(T '出站 25 端口' 'Outbound port 25')" "$(ok "$(T '开放(能直接发信)' 'open (can send mail directly)')")"
  else row "$(T '出站 25 端口' 'Outbound port 25')" "$(warn "$(T '被封(多数云厂商默认封)' 'blocked (most clouds block it by default)')")"; fi
fi

printf '\n%s\n' "$(dim "$(T "完整报告:$SITE/ip/<IP>   判定方法:$SITE/method/" "Full report: $SITE/en/ip/<IP>   Method: $SITE/en/method/")")"
