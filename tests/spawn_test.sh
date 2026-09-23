#!/usr/bin/env bash
# Behavior checks for spawn.sh and the model registry. No live CLIs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPAWN="$ROOT/scripts/spawn.sh"
REG="$ROOT/scripts/harness_registry.py"
BASH_BIN="$(command -v bash)"
PYTHON=""
for candidate in python python3; do
  if command -v "$candidate" >/dev/null && "$candidate" -c 'import sys; assert sys.version_info.major == 3' 2>/dev/null; then
    PYTHON="$candidate"
    break
  fi
done
[[ -n "$PYTHON" ]] || { echo "Python 3 required" >&2; exit 2; }

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

new_run() {
  local run
  run="$(mktemp -d "${TMPDIR:-/tmp}/hs-spawn.XXXXXX")"
  WORK+=("$run")
  printf 'Task\n' >"$run/brief.md"
  printf '%s\n' "$run"
}

run_cmd() {
  local outf errf
  outf="$(mktemp "${TMPDIR:-/tmp}/hs-out.XXXXXX")"
  errf="$(mktemp "${TMPDIR:-/tmp}/hs-err.XXXXXX")"
  WORK+=("$outf" "$errf")
  set +e
  "$@" >"$outf" 2>"$errf"
  ec=$?
  set -e
  out="$(cat "$outf")"
  err="$(cat "$errf")"
}

# Spoken Astra resolves to gpt-6-astra and does not invent an effort.
run="$(new_run)"
run_cmd "$BASH_BIN" "$SPAWN" --model Astra --project "$ROOT" --run "$run" --dry-run
if [[ "$ec" -eq 0 && "$out" == *"-m gpt-6-astra"* && "$out" == *"codex exec"* && "$out" != *"model_reasoning_effort"* && "$out" != *"--mode"* ]]; then
  ok "Astra dry-run resolves without an effort flag"
else
  fail_msg "Astra dry-run (exit=$ec out=$out err=$err)"
fi

# Opus 5.5 resolves, and a chosen effort is passed through.
run="$(new_run)"
run_cmd "$BASH_BIN" "$SPAWN" --model "Opus 5.5" --effort high --project "$ROOT" --run "$run" --dry-run
if [[ "$ec" -eq 0 && "$out" == *"--model claude-opus-5-5"* && "$out" == *"--effort high"* && "$out" == *"Edit"* && "$out" == *"Write"* ]]; then
  ok "Opus 5.5 dry-run pins the id and effort"
else
  fail_msg "Opus 5.5 dry-run (exit=$ec out=$out err=$err)"
fi

# A name from another CLI is rejected.
run="$(new_run)"
run_cmd "$BASH_BIN" "$SPAWN" --backend claude --model Astra --project "$ROOT" --run "$run" --dry-run
if [[ "$ec" -eq 2 && "$err" == *"not a claude model"* ]]; then
  ok "Astra is rejected on claude"
else
  fail_msg "Astra on claude (exit=$ec err=$err)"
fi

# Haiku has no effort levels.
run="$(new_run)"
run_cmd "$BASH_BIN" "$SPAWN" --model Haiku --effort high --project "$ROOT" --run "$run" --dry-run
if [[ "$ec" -eq 2 && "$err" == *"does not take --effort"* ]]; then
  ok "Haiku rejects effort"
else
  fail_msg "Haiku effort (exit=$ec err=$err)"
fi

run_cmd "$BASH_BIN" "$SPAWN" --mode review
if [[ "$ec" -eq 2 && "$err" == *"--mode was removed"* ]]; then
  ok "--mode is rejected"
else
  fail_msg "--mode (exit=$ec err=$err)"
fi

run="$(new_run)"
run_cmd env HARNESS_SUBAGENT_RUN="$run" "$BASH_BIN" "$SPAWN" --model Astra --project "$ROOT" --run "$run" --dry-run
if [[ "$ec" -eq 2 && "$err" == *"nested spawn refused"* ]]; then
  ok "nested spawn is refused"
else
  fail_msg "nested (exit=$ec err=$err)"
fi

limit() {
  printf '%s' "$1" | "$PYTHON" "$REG" limit --now "$2"
}

got="$(limit 'You have hit your session limit · resets 3:45pm' '2026-09-22T15:00:00')"
if [[ "$got" == "wait 2715" ]]; then
  ok "clock reset within 24h waits"
else
  fail_msg "clock reset got '$got'"
fi

got="$(limit 'You have hit your weekly limit · resets Mon 12:00am' '2026-09-22T12:00:00')"
if [[ "$got" == "stop" ]]; then
  ok "weekday reset beyond 24h stops"
else
  fail_msg "weekday reset got '$got'"
fi

got="$(limit 'Try again at 2026-09-22T14:00:00' '2026-09-22T12:00:00')"
if [[ "$got" == "wait 7215" ]]; then
  ok "absolute reset within 24h waits"
else
  fail_msg "absolute reset got '$got'"
fi

got="$(limit 'Try again at 2026-09-25T12:00:00' '2026-09-22T12:00:00')"
if [[ "$got" == "stop" ]]; then
  ok "absolute reset beyond 24h stops"
else
  fail_msg "far reset got '$got'"
fi

got="$(limit "You've hit your usage limit. Try again later." '2026-09-22T12:00:00')"
if [[ "$got" == "stop" ]]; then
  ok "limit text without a time stops"
else
  fail_msg "no time got '$got'"
fi

run="$(new_run)"
run_cmd "$BASH_BIN" "$SPAWN" --backend agy --model gemini-test --project "$ROOT" --run "$run" --dry-run
if [[ "$ec" -eq 0 && "$out" == *"--dangerously-skip-permissions"* && "$out" != *"--add-dir"* ]]; then
  ok "agy dry-run writes in the project and not the run dir"
else
  fail_msg "agy dry-run (exit=$ec out=$out err=$err)"
fi

run="$(new_run)"
run_cmd "$BASH_BIN" "$SPAWN" --backend cursor --model composer-2 --effort high --project "$ROOT" --run "$run" --dry-run
if [[ "$ec" -eq 0 ]] && printf '%s' "$out" | grep -F -q 'cursor-agent' && printf '%s' "$out" | grep -F -q 'effort=high'; then
  ok "cursor effort is written into the model id"
else
  fail_msg "cursor dry-run (exit=$ec out=$out err=$err)"
fi

got="$(limit 'Retry-After: 30' '2026-09-22T12:00:00')"
if [[ "$got" == "wait 45" ]]; then
  ok "Retry-After waits with the buffer"
else
  fail_msg "Retry-After got '$got'"
fi

echo
echo "passed=$pass failed=$fail"
[[ "$fail" -eq 0 ]]
