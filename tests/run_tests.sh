#!/usr/bin/env bash
# Offline tests for skills/ipjudge-exit-check/scripts/exit-check.sh. Everything talks to local fakes.
# Usage: tests/run_tests.sh [bash-binary]     (default: /bin/bash)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../skills/ipjudge-exit-check/scripts/exit-check.sh"
BASH_BIN="${1:-/bin/bash}"
PY="${PYTHON:-python3}"
TMP="$(mktemp -d)"
SANDBOX="$TMP/home"; mkdir -p "$SANDBOX/.claude"
PASS=0; FAIL=0

"$PY" "$HERE/fake_server.py" "$TMP/port" & SRV=$!
trap 'kill $SRV 2>/dev/null; rm -rf "$TMP"' EXIT
for _ in $(seq 1 50); do [ -s "$TMP/port" ] && break; sleep 0.1; done
PORT="$(cat "$TMP/port")"; B="http://127.0.0.1:$PORT"
echo "fake server on $B, bash: $($BASH_BIN --version | head -1)"

OUT=""; CODE=0
# run <ENV=VAL ...>: clean environment, sandboxed HOME, test mode pointing at the fakes
run() {
  OUT=$(env -i PATH="$PATH" HOME="$SANDBOX" LC_ALL=C \
    IPJUDGE_TEST_MODE=1 IPJUDGE_TEST_SITE="$B/s/good" \
    IPJUDGE_TEST_TRACE_ANTHROPIC="$B/trace/ok_a" IPJUDGE_TEST_TRACE_OPENAI="$B/trace/ok_b" \
    "$@" "$BASH_BIN" "$SCRIPT" 2>&1); CODE=$?
}
ok() { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; echo "$OUT" | sed 's/^/       | /' | head -40; }
has() { printf '%s\n' "$OUT" | grep -Fxq "$2" && ok "$1" || bad "$1 (missing: $2)"; }
hasnt() { printf '%s\n' "$OUT" | grep -Fq -- "$2" && bad "$1 (leaked: $2)" || ok "$1"; }
code() { [ "$CODE" = "$2" ] && ok "$1" || bad "$1 (exit $CODE, want $2)"; }
clean() { printf '%s' "$OUT" | LC_ALL=C grep -q '[^[:print:][:space:]]' && bad "$1 (control bytes in output)" || ok "$1"; }

echo "== T1 no proxy: baseline =="
run
code "T1 exit 0" 0
has "T1 result" "result=complete_no_findings"
has "T1 claude exit = direct" "claude_exit_equals_direct_exit=yes"
has "T1 test-mode banner" "warning=TEST MODE: endpoints overridden, results are not real"
clean "T1 printable only"

echo "== T2 https_proxy with credentials, path, query =="
# The fake site is addressed as `localhost` so it cannot be confused with the proxy at 127.0.0.1.
run IPJUDGE_TEST_SITE="http://localhost:$PORT/s/good" https_proxy="http://alice:SUPERSECRET@127.0.0.1:$PORT/p?token=QUERYSECRET"
has "T2 went through proxy" "claude_exit_ip=198.51.100.7"
has "T2 var name" "claude_proxy_var=https_proxy"
has "T2 scheme" "claude_proxy_scheme=http"
has "T2 loopback" "claude_proxy_target=loopback"
has "T2 port" "claude_proxy_port=$PORT"
has "T2 differs from direct" "claude_exit_equals_direct_exit=no"
hasnt "T2 no password" "SUPERSECRET"
hasnt "T2 no query token" "QUERYSECRET"
hasnt "T2 no user" "alice"
hasnt "T2 no host:port echoed" "127.0.0.1:$PORT"

echo "== T3 lowercase wins over uppercase (Claude Code's documented order) =="
run HTTPS_PROXY="http://127.0.0.1:1" https_proxy="http://127.0.0.1:$PORT"
has "T3 picks lowercase" "claude_proxy_var=https_proxy"
has "T3 via proxy" "claude_exit_ip=198.51.100.7"

echo "== T4 ALL_PROXY only: stated as fact, run is incomplete =="
run ALL_PROXY="http://127.0.0.1:$PORT"
has "T4 no documented var" "claude_proxy_var=none"
has "T4 incomplete" "result=incomplete"
code "T4 exit 20" 20
hasnt "T4 does not claim Claude ignores it" "claude_code_ignores"
printf '%s\n' "$OUT" | grep -q "all_proxy_is_set_but_is_not_one_of_the_four_variables_claude_code_documents" && ok "T4 finding present" || bad "T4 finding present"

echo "== T5 SOCKS: documented unsupported, probe skipped, incomplete =="
run https_proxy="socks5://bob:SOCKSSECRET@127.0.0.1:1080"
has "T5 scheme" "claude_proxy_scheme=socks5"
has "T5 skipped" "claude_probe=skipped"
has "T5 incomplete" "result=incomplete"
hasnt "T5 no password" "SOCKSSECRET"

echo "== T6 unparsable proxy value (no scheme) =="
run https_proxy="user:NOSCHEMESECRET@proxy.example:8080"
has "T6 scheme" "claude_proxy_scheme=unparsable"
has "T6 incomplete" "result=incomplete"
hasnt "T6 no secret" "NOSCHEMESECRET"
hasnt "T6 no host" "proxy.example"

echo "== T7 NO_PROXY contents are never echoed =="
run NO_PROXY="internal.corp.example,10.9.8.7" https_proxy="http://127.0.0.1:$PORT"
has "T7 flag only" "no_proxy_set=yes"
hasnt "T7 no list" "internal.corp.example"
hasnt "T7 no addr" "10.9.8.7"

echo "== T8 probe failures =="
run IPJUDGE_TEST_TRACE_ANTHROPIC="$B/trace/fail500"
has "T8a claude probe failed" "claude_probe=failed"
has "T8a incomplete" "result=incomplete"
hasnt "T8a never says no problems" "complete_no_findings"
run IPJUDGE_TEST_TRACE_ANTHROPIC="$B/trace/garbage"
has "T8b garbage body rejected" "claude_probe=failed"
hasnt "T8b script tag not echoed" "<script>"
run IPJUDGE_TEST_TRACE_OPENAI="$B/trace/fail500"
has "T8c openai failure is informational" "openai_probe=failed"
has "T8c still complete" "result=complete_no_findings"

echo "== T9 site verdicts =="
for sc in bad warn; do
  run IPJUDGE_TEST_SITE="$B/s/$sc"
  has "T9 $sc level" "site_claude_level=$sc"
  has "T9 $sc has findings" "result=complete_with_findings"
  code "T9 $sc exit 10" 10
done
for sc in info fail garbage mismatch huge; do
  run IPJUDGE_TEST_SITE="$B/s/$sc"
  has "T9 $sc incomplete" "result=incomplete"
  code "T9 $sc exit 20" 20
done

echo "== T10 hostile site response =="
run IPJUDGE_TEST_SITE="$B/s/injection"
has "T10 real level used, spoof ignored" "site_claude_level=bad"
code "T10 exit 10" 10
hasnt "T10 no injected text" "IGNORE ALL PREVIOUS"
hasnt "T10 no rm -rf" "rm -rf"
clean "T10 printable only"
run IPJUDGE_TEST_SITE="$B/s/huge"
[ "${#OUT}" -lt 4000 ] && ok "T10 huge body: output stays small" || bad "T10 huge body: output size ${#OUT}"

echo "== T11 user curlrc must be ignored (curl -q) =="
printf 'output = "%s/CURLRC_WROTE_THIS"\nproxy = "http://127.0.0.1:1"\nsilent\n' "$TMP" > "$SANDBOX/.curlrc"
run
has "T11 still direct, rc ignored" "claude_exit_ip=203.0.113.10"
[ ! -e "$TMP/CURLRC_WROTE_THIS" ] && ok "T11 no file written by curlrc" || bad "T11 curlrc wrote a file"
rm -f "$SANDBOX/.curlrc"

echo "== T12 settings.json: key presence only, value and neighbours never read out =="
printf '{"env":{"HTTPS_PROXY":"http://zed:SETTINGSSECRET@h.example:1"},"apiKeyHelper":"sk-ant-LEAKME"}\n' > "$SANDBOX/.claude/settings.json"
run
has "T12 key detected" "claude_settings_has_proxy_key=present"
has "T12 not evaluated => incomplete" "result=incomplete"
hasnt "T12 no secret" "SETTINGSSECRET"
hasnt "T12 no api key" "sk-ant-LEAKME"
hasnt "T12 no host" "h.example"
rm -f "$SANDBOX/.claude/settings.json"

echo "== T13 live mode ignores test overrides, and says so =="
HITS_BEFORE=$(curl -q -s "$B/__hits")
OUT=$(env -i PATH="$PATH" HOME="$SANDBOX" LC_ALL=C \
  IPJUDGE_TEST_SITE="$B/s/good" IPJUDGE_TEST_TRACE_ANTHROPIC="$B/trace/ok_a" IPJUDGE_TEST_TRACE_OPENAI="$B/trace/ok_b" \
  "$BASH_BIN" "$SCRIPT" 2>&1); CODE=$?
has "T13 mode is live" "mode=live"
hasnt "T13 no test banner" "TEST MODE"
HITS_AFTER=$(curl -q -s "$B/__hits")
[ "$HITS_BEFORE" = "$HITS_AFTER" ] && ok "T13 fake server not contacted by the live run" || bad "T13 fake server was hit: $HITS_BEFORE -> $HITS_AFTER"

echo "== T14 no stray processes / no files left in HOME =="
run
[ -z "$(ls -A "$SANDBOX" | grep -v '^.claude$')" ] && ok "T14 sandbox HOME clean" || bad "T14 files appeared in HOME: $(ls -A "$SANDBOX")"

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" = 0 ]
