#!/usr/bin/env bash
# Real-CLI smokes for Auto-mode flags. Run from Git Bash: bash tests/hello_world.sh
# Parse checks always run when the binary exists. Live one-shot per backend on PATH.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPAWN="$ROOT/scripts/spawn.sh"
BASH_BIN="$(command -v bash)"

pass=0
fail=0
WORK=()

cleanup() {
  local d
  for d in "${WORK[@]+"${WORK[@]}"}"; do
    rm -rf "$d"
  done
}
trap cleanup EXIT

ok() { echo "ok - $*"; pass=$((pass + 1)); }
fail_msg() { echo "FAIL: $*" >&2; fail=$((fail + 1)); }
skip() { echo "ok - skip $*"; pass=$((pass + 1)); }

has_bin() { command -v "$1" >/dev/null 2>&1; }

run_cmd() {
  local outf errf
  outf="$(mktemp "${TMPDIR:-/tmp}/hs-hw-out.XXXXXX")"
  errf="$(mktemp "${TMPDIR:-/tmp}/hs-hw-err.XXXXXX")"
  WORK+=("$outf" "$errf")
  set +e
  "$@" >"$outf" 2>"$errf"
  ec=$?
  set -e
  out="$(cat "$outf")"
  err="$(cat "$errf")"
}

# --- parse ---

if has_bin codex; then
  run_cmd codex exec --ask-for-approval never --help
  if [[ "$ec" -ne 0 && ( "$err" == *"--ask-for-approval"* || "$out" == *"--ask-for-approval"* ) ]]; then
    ok "codex exec rejects --ask-for-approval"
  else
    fail_msg "codex exec should reject --ask-for-approval (exit=$ec err=${err//$'\n'/ | })"
  fi
  run_cmd codex exec --approve-for-me --help
  if [[ "$ec" -eq 0 && "$out" == *"codex exec"* ]]; then
    ok "codex exec accepts --approve-for-me"
  else
    fail_msg "codex exec --approve-for-me --help (exit=$ec out=${out//$'\n'/ | } err=${err//$'\n'/ | })"
  fi
else
  skip "codex not on PATH (parse)"
fi

if has_bin claude; then
  run_cmd claude --help
  if [[ "$out" == *'"auto"'* || "$out" == *'choices: "acceptEdits", "auto"'* || "$err$out" == *"\"auto\""* ]]; then
    ok "claude --help lists permission-mode auto"
  else
    # help may put auto on the next line after choices
    if echo "$out$err" | grep -q '"auto"'; then
      ok "claude --help lists permission-mode auto"
    else
      fail_msg "claude --help missing auto (exit=$ec)"
    fi
  fi
else
  skip "claude not on PATH (parse)"
fi

if has_bin grok; then
  run_cmd grok --help
  if echo "$out$err" | grep -qE '\[possible values:.*\bauto\b'; then
    ok "grok --help lists permission-mode auto"
  else
    fail_msg "grok --help missing auto (exit=$ec)"
  fi
else
  skip "grok not on PATH (parse)"
fi

if has_bin agy; then
  run_cmd agy --help
  if echo "$out$err" | grep -q -- '--print'; then
    ok "agy --help lists --print"
  else
    fail_msg "agy --help missing --print (exit=$ec)"
  fi
  if echo "$out$err" | grep -q -- '--dangerously-skip-permissions'; then
    ok "agy --help lists --dangerously-skip-permissions"
  else
    fail_msg "agy --help missing --dangerously-skip-permissions (exit=$ec)"
  fi
else
  skip "agy not on PATH (parse)"
fi

# --- live ---

live_one() {
  local backend="$1" run
  if ! has_bin "$backend"; then
    skip "$backend not on PATH (live)"
    return 0
  fi
  run="$(mktemp -d "${TMPDIR:-/tmp}/hs-hw.XXXXXX")"
  WORK+=("$run")
  cat >"$run/brief.md" <<'EOF'
Reply with exactly these two lines and nothing else. Do not use tools.
VERDICT — HELLO_WORLD
HELLO_WORLD
EOF
  run_cmd "$BASH_BIN" "$SPAWN" --backend "$backend" --mode review --project "$ROOT" --run "$run" --effort low
  if [[ "$ec" -eq 0 && -s "$run/last.md" ]] && grep -q 'HELLO_WORLD' "$run/last.md"; then
    ok "$backend live HELLO_WORLD"
  else
    fail_msg "$backend live HELLO_WORLD (exit=$ec last=$(head -c 240 "$run/last.md" 2>/dev/null || true) err=$(head -c 240 "$run/stderr.log" 2>/dev/null || true) spawnerr=${err//$'\n'/ | })"
  fi
}

live_one claude
live_one codex
live_one grok
live_one agy

echo
echo "passed=$pass failed=$fail"
[[ "$fail" -eq 0 ]]
