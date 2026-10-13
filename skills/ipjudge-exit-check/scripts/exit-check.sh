#!/usr/bin/env bash
# exit-check.sh (ipjudge-exit-check): read-only terminal exit self-check, for coding agents.
#
# What it does (nothing else):
#   1. Reads PROXY-RELATED environment variable NAMES and the scheme / loopback-or-remote / port
#      of the one Claude Code would use. Never prints hosts, credentials, paths or NO_PROXY contents.
#   2. Asks Cloudflare's /cdn-cgi/trace on api.anthropic.com and api.openai.com which IP and
#      country they see, plus a no-proxy baseline.
#   3. Looks that exit IP up on ipjudge.org (one request) and keeps only enumerated / numeric fields.
# It installs nothing, changes no setting, uploads nothing except that one IP lookup.
#
# Output: plain `key=value` lines (English, stable keys). Exit code:
#   0 = complete, nothing to report   10 = complete, findings present   20 = INCOMPLETE
# An incomplete run must never be summarised as "no problems".
#
# Requires bash (3.2+), curl, grep, sed, head, tr. No python / jq.

set -u
export LC_ALL=C

VERSION="0.1.0"
SITE="https://ipjudge.org"
TRACE_ANTHROPIC="https://api.anthropic.com/cdn-cgi/trace"
TRACE_OPENAI="https://api.openai.com/cdn-cgi/trace"
PROTO="=https"
MODE="live"

# Endpoints are fixed. They can only be overridden in an explicit test mode, which is announced.
if [ "${IPJUDGE_TEST_MODE:-}" = "1" ]; then
  MODE="TEST"
  SITE="${IPJUDGE_TEST_SITE:-$SITE}"
  TRACE_ANTHROPIC="${IPJUDGE_TEST_TRACE_ANTHROPIC:-$TRACE_ANTHROPIC}"
  TRACE_OPENAI="${IPJUDGE_TEST_TRACE_OPENAI:-$TRACE_OPENAI}"
  PROTO="=http,https"
fi

FINDINGS=""
REASONS=""
add_finding() { FINDINGS="$FINDINGS $1"; }
add_reason() { REASONS="$REASONS $1"; }
kv() { printf '%s=%s\n' "$1" "$2"; }

RE_V4='^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$'
RE_CC='^[A-Z][A-Z0-9]$'
RE_PORT='^[0-9]{1,5}$'
RE_URL='^([A-Za-z][A-Za-z0-9+.-]*)://(.*)$'
RE_BRACKET_HP='^\[(.*)\]:([0-9]+)$'
RE_HOSTPORT='^([^:]*):([0-9]+)$'

# Strict IP check: nothing else may reach the output.
valid_ip() {
  local s="$1" i
  [ "${#s}" -ge 2 ] && [ "${#s}" -le 45 ] || return 1
  if [[ $s =~ $RE_V4 ]]; then
    for i in 1 2 3 4; do
      [ "$((10#${BASH_REMATCH[i]}))" -le 255 ] || return 1
    done
    return 0
  fi
  case "$s" in
    *:*:*) printf '%s' "$s" | grep -Eq '^[0-9A-Fa-f:]+$' ;;
    *) return 1 ;;
  esac
}

# fetch <url> [max-seconds]: body on stdout (hard-capped), curl's exit status as return value.
#   -q first = ignore the user's ~/.curlrc; protocol locked; no redirects; size capped.
fetch() {
  local url="$1" mt="${2:-10}"
  # shellcheck disable=SC2086  # FETCH_IPFLAG is empty or a single curl flag, on purpose
  curl -q -sS -f $FETCH_IPFLAG --max-time "$mt" --connect-timeout 6 \
    --proto "$PROTO" --proto-redir "$PROTO" --max-redirs 0 \
    --max-filesize 65536 -A "ipjudge-exit-check/$VERSION" \
    "$url" 2>/dev/null | head -c 16384
  return "${PIPESTATUS[0]}"
}
FETCH_IPFLAG=""

clear_proxy_env() {
  unset https_proxy HTTPS_PROXY http_proxy HTTP_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
}

# probe_trace <url> <claude|direct|plain>: prints "ip cc" on success, nothing on failure.
#   claude : only the variable Claude Code would use is passed on (to the child only, never via argv)
#   direct : all proxy variables removed
#   plain  : whatever curl itself would do with the current environment
# Runs in a subshell (called from $( )), so the env changes below never leak into the main script.
# The case lives in a function on purpose: bash 3.2 cannot parse `case` directly inside $( ).
fetch_as() {
  local how="$1" url="$2"
  case "$how" in
    claude)
      clear_proxy_env
      if [ -n "$CLAUDE_PROXY" ]; then export https_proxy="$CLAUDE_PROXY" http_proxy="$CLAUDE_PROXY"; fi
      if [ -n "$NOPROXY_VAL" ]; then export no_proxy="$NOPROXY_VAL"; fi
      ;;
    direct) clear_proxy_env ;;
    plain) : ;;
  esac
  fetch "$url" 10
}

probe_trace() {
  local url="$1" how="$2" body rc ip cc
  body=$(fetch_as "$how" "$url")
  rc=$?
  PROBE_IP=""; PROBE_CC=""
  [ "$rc" -eq 0 ] || { PROBE_RC="$rc"; return 1; }
  ip=$(printf '%s\n' "$body" | sed -n 's/^ip=//p' | head -n1)
  cc=$(printf '%s\n' "$body" | sed -n 's/^loc=//p' | head -n1)
  if valid_ip "$ip" && [[ $cc =~ $RE_CC ]]; then
    PROBE_IP="$ip"; PROBE_CC="$cc"; PROBE_RC=0
    return 0
  fi
  PROBE_RC="bad_body"
  return 1
}
PROBE_RC=""; PROBE_IP=""; PROBE_CC=""

# ---------- 1. proxy configuration: names and shape only ----------
kv tool_version "$VERSION"
kv mode "$MODE"
[ "$MODE" = "TEST" ] && kv warning "TEST MODE: endpoints overridden, results are not real"

SET_NAMES=""
for v in https_proxy HTTPS_PROXY http_proxy HTTP_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY; do
  [ -n "${!v:-}" ] && SET_NAMES="$SET_NAMES $v"
done
kv proxy_env_names_set "${SET_NAMES# }"

# Claude Code's documented order: https_proxy, HTTPS_PROXY, http_proxy, HTTP_PROXY.
CLAUDE_PROXY=""; CLAUDE_PROXY_VAR=""
for v in https_proxy HTTPS_PROXY http_proxy HTTP_PROXY; do
  if [ -n "${!v:-}" ]; then CLAUDE_PROXY="${!v}"; CLAUDE_PROXY_VAR="$v"; break; fi
done
NOPROXY_VAL="${no_proxy:-${NO_PROXY:-}}"
kv claude_proxy_var "${CLAUDE_PROXY_VAR:-none}"
kv no_proxy_set "$([ -n "$NOPROXY_VAL" ] && echo yes || echo no)"

C_SCHEME="none"; C_TARGET="n/a"; C_PORT="n/a"; SKIP_CLAUDE=0
if [ -n "$CLAUDE_PROXY" ]; then
  if [[ $CLAUDE_PROXY =~ $RE_URL ]]; then
    sch=$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
    rest="${BASH_REMATCH[2]}"; rest="${rest%%/*}"; rest="${rest##*@}"
    if [[ $rest =~ $RE_BRACKET_HP ]]; then h="${BASH_REMATCH[1]}"; p="${BASH_REMATCH[2]}"
    elif [[ $rest =~ $RE_HOSTPORT ]]; then h="${BASH_REMATCH[1]}"; p="${BASH_REMATCH[2]}"
    else h="$rest"; p=""; fi
    case "$sch" in
      http|https) C_SCHEME="$sch" ;;
      socks4|socks4a|socks5|socks5h)
        C_SCHEME="$sch"; SKIP_CLAUDE=1
        add_finding claude_code_documentation_says_socks_proxies_are_not_supported
        add_reason claude_probe_skipped_unsupported_proxy_type ;;
      *) C_SCHEME="other"; SKIP_CLAUDE=1
         add_finding claude_proxy_scheme_not_http_or_https
         add_reason claude_probe_skipped_unrecognized_proxy_scheme ;;
    esac
    case "$h" in 127.*|localhost|::1) C_TARGET="loopback" ;; *) C_TARGET="remote" ;; esac
    if [[ $p =~ $RE_PORT ]] && [ "$p" -le 65535 ]; then C_PORT="$p"; fi
  else
    C_SCHEME="unparsable"; SKIP_CLAUDE=1
    add_finding claude_proxy_value_has_no_scheme_documentation_says_claude_code_refuses_to_start
    add_reason claude_probe_skipped_unparsable_proxy_value
  fi
fi
kv claude_proxy_scheme "$C_SCHEME"
kv claude_proxy_target "$C_TARGET"
kv claude_proxy_port "$C_PORT"

# ALL_PROXY is not in the documented list. State the fact; do not guess what Claude Code does with it.
if [ -z "$CLAUDE_PROXY" ] && { [ -n "${all_proxy:-}" ] || [ -n "${ALL_PROXY:-}" ]; }; then
  add_finding all_proxy_is_set_but_is_not_one_of_the_four_variables_claude_code_documents
  add_reason claude_effective_proxy_unverified_all_proxy_only
fi

# settings.json: only test whether a proxy-looking key exists. The value is never read or printed.
SETTINGS="${HOME:-/nonexistent}/.claude/settings.json"
SET_KEY="unreadable_or_absent"
if [ -r "$SETTINGS" ]; then
  if head -c 262144 "$SETTINGS" 2>/dev/null | grep -Eiq '"(https?_proxy|all_proxy|no_proxy)"[[:space:]]*:'; then
    SET_KEY="present"
  else
    SET_KEY="absent"
  fi
fi
kv claude_settings_has_proxy_key "$SET_KEY"
if [ "$SET_KEY" = "present" ] && [ -z "$CLAUDE_PROXY" ]; then
  add_reason claude_settings_proxy_key_not_evaluated
fi

# ---------- 2. what the endpoints see ----------
CLAUDE_IP=""; CLAUDE_CC=""
if [ "$SKIP_CLAUDE" = "1" ]; then
  kv claude_probe "skipped"
elif probe_trace "$TRACE_ANTHROPIC" claude; then
  CLAUDE_IP="$PROBE_IP"; CLAUDE_CC="$PROBE_CC"
  kv claude_probe "ok"
  kv claude_exit_ip "$CLAUDE_IP"
  kv claude_exit_country "$CLAUDE_CC"
else
  kv claude_probe "failed"
  kv claude_probe_detail "curl_exit_$PROBE_RC"
  add_reason claude_probe_failed
fi

if probe_trace "$TRACE_OPENAI" plain; then
  OAI_IP="$PROBE_IP"
  kv openai_probe "ok_plain_curl_semantics"
  kv openai_exit_ip "$PROBE_IP"
  kv openai_exit_country "$PROBE_CC"
else
  OAI_IP=""
  kv openai_probe "failed"
  kv openai_probe_detail "curl_exit_$PROBE_RC"
fi

if probe_trace "$TRACE_ANTHROPIC" direct; then
  DIR_IP="$PROBE_IP"
  kv direct_probe "ok"
  kv direct_exit_ip "$PROBE_IP"
  kv direct_exit_country "$PROBE_CC"
else
  DIR_IP=""
  kv direct_probe "unreachable_without_proxy"
fi

if [ -n "$CLAUDE_IP" ]; then
  [ -n "$DIR_IP" ] && kv claude_exit_equals_direct_exit "$([ "$CLAUDE_IP" = "$DIR_IP" ] && echo yes || echo no)"
  [ -n "$OAI_IP" ] && kv claude_exit_equals_openai_exit "$([ "$CLAUDE_IP" = "$OAI_IP" ] && echo yes || echo no)"
fi

# ---------- 3. what ipjudge.org says about the Claude Code exit IP ----------
# Only enumerated / numeric / boolean fields are kept. Free-text fields in the response are dropped.
jget() { printf '%s' "$J" | grep -Eo "$1" | head -n1; }
if [ -n "$CLAUDE_IP" ]; then
  FETCH_IPFLAG=""
  J=$(fetch "$SITE/api/ip/$CLAUDE_IP" 15); lrc=$?
  if [ "$lrc" -ne 0 ]; then
    kv site_lookup "failed"
    kv site_lookup_detail "curl_exit_$lrc"
    add_reason site_lookup_failed
  elif ! printf '%s' "$J" | grep -Fq "\"ip\":\"$CLAUDE_IP\""; then
    kv site_lookup "unexpected_response"
    add_reason site_lookup_unexpected_response
  else
    kind=$(jget '"kind":"[a-z_]{1,16}"' | sed 's/.*:"\(.*\)"/\1/')
    score=$(jget '"score":[0-9]{1,3}' | sed 's/.*://')
    grade=$(jget '"grade":"[A-F][+-]?"' | sed 's/.*:"\(.*\)"/\1/')
    limited=$(jget '"limited":(true|false)' | sed 's/.*://')
    clevel=$(jget '"name":"Claude","level":"(good|info|warn|bad)"' | sed 's/.*"level":"\(.*\)"/\1/')
    kv site_lookup "ok"
    kv site_ip_kind "${kind:-unknown}"
    kv site_purity_score "${score:-unknown}"
    kv site_purity_grade "${grade:-unknown}"
    kv site_region_limited "${limited:-unknown}"
    kv site_claude_level "${clevel:-unknown}"
    kv site_detail_url "$SITE/ip/$CLAUDE_IP"
    case "$clevel" in
      bad) add_finding ipjudge_site_marks_this_exit_as_not_acceptable_for_claude ;;
      warn) add_finding ipjudge_site_marks_this_exit_as_usable_with_caveats_for_claude ;;
      good) : ;;
      info) add_reason site_could_not_determine_claude_level ;;
      *) add_reason site_claude_level_unrecognised ;;
    esac
  fi
elif [ "$SKIP_CLAUDE" != "1" ]; then
  kv site_lookup "not_attempted_no_exit_ip"
fi

# ---------- 4. result ----------
kv findings "${FINDINGS# }"
kv incomplete_reasons "${REASONS# }"
if [ -n "$REASONS" ]; then RESULT="incomplete"; CODE=20
elif [ -n "$FINDINGS" ]; then RESULT="complete_with_findings"; CODE=10
else RESULT="complete_no_findings"; CODE=0; fi
kv result "$RESULT"
kv exit_code "$CODE"
kv note_1 "A reachable trace endpoint shows which IP and country the host sees. It does not show that an account, login or API call will work."
kv note_2 "Not covered: IPv6, Codex-specific proxy rules, NO_PROXY matching, values inside settings.json, browser traffic."
kv note_3 "Only one outbound lookup leaves this machine for ipjudge.org: the exit IP above."
exit "$CODE"
