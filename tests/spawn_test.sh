#!/usr/bin/env bash
# Tests for scripts/spawn.sh. Run from Git Bash: bash tests/spawn_test.sh
# Does not invoke real claude/codex/grok — dry-run plus PATH-isolated stubs.
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

LAST_TMP=""

mkwork() {
  LAST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/hs-test.XXXXXX")"
  WORK+=("$LAST_TMP")
}

make_run() {
  mkwork
  printf 'brief body %s\n' "$(basename "$LAST_TMP")" >"$LAST_TMP/brief.md"
}

# Capture spawn without aborting the runner (set -e).
run_spawn() {
  local outf errf
  outf="$(mktemp "${TMPDIR:-/tmp}/hs-out.XXXXXX")"
  errf="$(mktemp "${TMPDIR:-/tmp}/hs-err.XXXXXX")"
  WORK+=("$outf" "$errf")
  set +e
  "$BASH_BIN" "$SPAWN" "$@" >"$outf" 2>"$errf"
  ec=$?
  set -e
  out="$(cat "$outf")"
  err="$(cat "$errf")"
}

n_occ() {
  local n="$1" h="$2" t c=0
  t="$h"
  while [[ -n "$t" && "$t" == *"$n"* ]]; do
    t="${t#*"$n"}"
    c=$((c + 1))
  done
  printf '%s' "$c"
}

expect_die() {
  local desc="$1" needle="${2-spawn.sh:}"
  shift 2
  run_spawn "$@"
  if [[ "$ec" -eq 2 && "$err" == *"$needle"* ]]; then
    ok "$desc"
  else
    fail_msg "$desc (exit=$ec err=${err//$'\n'/ | })"
  fi
}

expect_ok() {
  local desc="$1"
  shift
  run_spawn "$@"
  if [[ "$ec" -eq 0 ]]; then
    ok "$desc"
  else
    fail_msg "$desc (exit=$ec err=${err//$'\n'/ | } out=${out//$'\n'/ | })"
  fi
}

# --- parser ---

expect_die "missing --backend" "missing --backend" --project "$ROOT" --run "$ROOT"
expect_die "missing --project" "missing --project" --backend claude --run "$ROOT"
expect_die "missing --run" "missing --run" --backend claude --project "$ROOT"
expect_die "unknown argument" "unknown argument" --backend claude --project "$ROOT" --run "$ROOT" --nope
expect_die "invalid backend" "backend must be" --backend cursor --project "$ROOT" --run "$ROOT"
expect_die "self is not a spawn backend" "backend must be" --backend self --project "$ROOT" --run "$ROOT"
expect_die "orchestrator is not a spawn backend" "backend must be" --backend orchestrator --project "$ROOT" --run "$ROOT"
expect_die "invalid mode" "mode must be" --backend claude --mode sideways --project "$ROOT" --run "$ROOT"

make_run
HARNESS_SUBAGENT_RUN="/tmp/hs-parent-run" run_spawn \
  --backend claude --mode review --project "$ROOT" --run "$LAST_TMP" --dry-run
if [[ "$ec" -eq 2 && "$err" == *"nested spawn refused"* ]]; then
  ok "nested spawn refused when HARNESS_SUBAGENT_RUN differs"
else
  fail_msg "nested spawn refused (exit=$ec err=${err//$'\n'/ | })"
fi

make_run
HARNESS_SUBAGENT_RUN="$LAST_TMP" run_spawn \
  --backend claude --mode review --project "$ROOT" --run "$LAST_TMP" --dry-run
if [[ "$ec" -eq 2 && "$err" == *"nested spawn refused"* ]]; then
  ok "same-run HARNESS_SUBAGENT_RUN refused"
else
  fail_msg "same-run HARNESS_SUBAGENT_RUN refused (exit=$ec err=${err//$'\n'/ | })"
fi

for flag in --backend --mode --project --run --model --effort --image; do
  expect_die "trailing $flag" "missing value for $flag" \
    --backend claude --mode review --project "$ROOT" --run "$ROOT" "$flag"
done

expect_die "flag as --backend value" "missing value for --backend" \
  --backend --project "$ROOT" --run "$ROOT"
expect_die "flag as --mode value" "missing value for --mode" \
  --backend claude --mode --project "$ROOT" --run "$ROOT"
expect_die "flag as --project value" "missing value for --project" \
  --backend claude --project --dry-run --run "$ROOT"
expect_die "flag as --run value" "missing value for --run" \
  --backend claude --project "$ROOT" --run --dry-run
expect_die "flag as --model value" "missing value for --model" \
  --backend claude --project "$ROOT" --run "$ROOT" --model --effort xhigh
expect_die "flag as --effort value" "missing value for --effort" \
  --backend claude --project "$ROOT" --run "$ROOT" --effort --model opus
expect_die "flag as --image value" "missing value for --image" \
  --backend claude --project "$ROOT" --run "$ROOT" --image --dry-run

for flag in --backend --mode --project --run --model --effort --image; do
  expect_die "empty $flag" "missing value for $flag" \
    --backend claude --mode review --project "$ROOT" --run "$ROOT" "$flag" ""
done

make_run
RUN="$LAST_TMP"
rm -f "$RUN/brief.md"
expect_die "missing brief.md" "brief.md missing or empty" \
  --backend claude --project "$ROOT" --run "$RUN" --dry-run
: >"$RUN/brief.md"
expect_die "empty brief.md file" "brief.md missing or empty" \
  --backend claude --project "$ROOT" --run "$RUN" --dry-run

expect_die "missing project dir" "project dir not found" \
  --backend claude --project /no/such/hs-project --run "$RUN" --dry-run
expect_die "missing run dir" "run dir not found" \
  --backend claude --project "$ROOT" --run /no/such/hs-run --dry-run

make_run
RUN="$LAST_TMP"
expect_die "invalid --model charset" "invalid --model" \
  --backend claude --project "$ROOT" --run "$RUN" --model 'bad;token' --dry-run
expect_die "invalid --effort charset" "invalid --effort" \
  --backend claude --project "$ROOT" --run "$RUN" --effort 'x high' --dry-run
expect_die "image not found" "image not found" \
  --backend codex --project "$ROOT" --run "$RUN" --image /no/such/hs.png --dry-run

# --- --help contract ---

run_spawn --help
if [[ "$ec" -eq 0 && "$out" == *"[--mode review|implement|visual]"* ]]; then
  ok "--help shows optional --mode"
else
  fail_msg "--help optional --mode (exit=$ec out=${out//$'\n'/ | })"
fi

# --- dry-run command shape ---

assert_one() {
  local desc="$1" needle="$2" hay="$3"
  local c
  c="$(n_occ "$needle" "$hay")"
  if [[ "$c" -eq 1 ]]; then
    ok "$desc"
  else
    fail_msg "$desc (count=$c needle=$needle)"
  fi
}

assert_none() {
  local desc="$1" needle="$2" hay="$3"
  local c
  c="$(n_occ "$needle" "$hay")"
  if [[ "$c" -eq 0 ]]; then
    ok "$desc"
  else
    fail_msg "$desc (count=$c needle=$needle)"
  fi
}

make_run
RUN="$LAST_TMP"

expect_ok "dry-run claude review" \
  --backend claude --mode review --project "$ROOT" --run "$RUN" --dry-run
assert_one "claude review permission-mode auto" "--permission-mode auto" "$out"
assert_none "claude review no plan" "--permission-mode plan" "$out"
assert_none "claude review no acceptEdits" "--permission-mode acceptEdits" "$out"
assert_one "claude review one permission-mode" "--permission-mode" "$out"
assert_one "claude review tools allowlist" "--tools Bash\\,Read\\,Glob\\,Grep" "$out"
assert_none "claude review no Edit" "Edit" "$out"
assert_none "claude review no Write" "Write" "$out"
assert_one "claude review --add-dir RUN" "--add-dir $RUN" "$out"
assert_one "claude review append-system-prompt" "--append-system-prompt" "$out"
assert_one "claude fresh session-id" "--session-id " "$out"
assert_none "claude persistence enabled" "--no-session-persistence" "$out"
[[ ! -e "$RUN/session-id" && ! -e "$RUN/session.json" ]] && ok 'dry-run publishes no identity' || fail_msg 'dry-run published identity'

expect_ok "dry-run claude implement" \
  --backend claude --mode implement --project "$ROOT" --run "$RUN" --dry-run
assert_one "claude implement permission-mode auto" "--permission-mode auto" "$out"
assert_none "claude implement no plan" "--permission-mode plan" "$out"
assert_none "claude implement no acceptEdits" "--permission-mode acceptEdits" "$out"
assert_one "claude implement one permission-mode" "--permission-mode" "$out"
assert_one "claude implement tools allowlist" "--tools Bash\\,Read\\,Edit\\,Write\\,Glob\\,Grep" "$out"

expect_ok "dry-run claude default mode is review" \
  --backend claude --project "$ROOT" --run "$RUN" --dry-run
assert_one "default mode auto" "--permission-mode auto" "$out"
assert_none "default mode no plan" "--permission-mode plan" "$out"
assert_none "default mode no acceptEdits" "--permission-mode acceptEdits" "$out"
assert_one "default mode one permission-mode" "--permission-mode" "$out"

expect_ok "dry-run codex review" \
  --backend codex --mode review --project "$ROOT" --run "$RUN" --dry-run
assert_one "codex review approve-for-me" "--approve-for-me" "$out"
assert_none "codex persistence enabled" "--ephemeral" "$out"
assert_one "codex JSON events" "--json" "$out"
assert_none "codex review no sandbox" "--sandbox" "$out"
assert_none "codex review no ask-for-approval" "--ask-for-approval" "$out"
assert_none "codex review no dangerous bypass" "--dangerously-bypass-approvals-and-sandbox" "$out"
[[ "$out" == *"-o $RUN/stdout.md -"* ]] && ok "codex -o before -" || fail_msg "codex -o before - ($out)"

expect_ok "dry-run codex implement" \
  --backend codex --mode implement --project "$ROOT" --run "$RUN" --dry-run
assert_one "codex implement approve-for-me" "--approve-for-me" "$out"
assert_none "codex implement no sandbox" "--sandbox" "$out"
assert_none "codex implement no ask-for-approval" "--ask-for-approval" "$out"
assert_none "codex implement no dangerous bypass" "--dangerously-bypass-approvals-and-sandbox" "$out"

mkwork
IMG="$LAST_TMP/shot.png"
printf 'png' >"$IMG"
expect_ok "dry-run codex visual images" \
  --backend codex --mode visual --project "$ROOT" --run "$RUN" --image "$IMG" --image "$IMG" --dry-run
assert_one "visual approve-for-me" "--approve-for-me" "$out"
assert_none "visual no sandbox" "--sandbox" "$out"
assert_none "visual no ask-for-approval" "--ask-for-approval" "$out"
# both -i flags before -o
img_pos="${out%%-o *}"
if [[ "$(n_occ " -i $IMG" "$img_pos")" -eq 2 && "$out" == *"-o $RUN/stdout.md -"* ]]; then
  ok "codex -i before -o"
else
  fail_msg "codex -i before -o ($out)"
fi

expect_ok "dry-run grok review" \
  --backend grok --mode review --project "$ROOT" --run "$RUN" --dry-run
assert_one "grok review permission-mode auto" "--permission-mode auto" "$out"
assert_none "grok review no plan" "--permission-mode plan" "$out"
assert_none "grok review no acceptEdits" "--permission-mode acceptEdits" "$out"
assert_one "grok review one permission-mode" "--permission-mode" "$out"
assert_none "grok review no sandbox" "--sandbox" "$out"
assert_one "grok --prompt-file brief" "--prompt-file $RUN/brief.md" "$out"
assert_one "grok fresh session-id" "--session-id " "$out"

expect_ok "dry-run grok implement" \
  --backend grok --mode implement --project "$ROOT" --run "$RUN" --dry-run
assert_one "grok implement permission-mode auto" "--permission-mode auto" "$out"
assert_none "grok implement no plan" "--permission-mode plan" "$out"
assert_none "grok implement no acceptEdits" "--permission-mode acceptEdits" "$out"
assert_one "grok implement one permission-mode" "--permission-mode" "$out"
assert_none "grok implement no sandbox" "--sandbox" "$out"

expect_ok "dry-run grok visual maps to review" \
  --backend grok --mode visual --project "$ROOT" --run "$RUN" --dry-run
assert_one "grok visual permission-mode auto" "--permission-mode auto" "$out"
assert_none "grok visual no plan" "--permission-mode plan" "$out"
assert_none "grok visual no acceptEdits" "--permission-mode acceptEdits" "$out"
assert_one "grok visual one permission-mode" "--permission-mode" "$out"
assert_none "grok visual no sandbox" "--sandbox" "$out"

expect_ok "dry-run agy review" \
  --backend agy --mode review --project "$ROOT" --run "$RUN" --dry-run
assert_one "agy review mode accept-edits" "--mode accept-edits" "$out"
assert_none "agy review no plan mode" "--mode plan" "$out"
assert_none "agy review no skip-permissions" "--dangerously-skip-permissions" "$out"
assert_none "agy review no sandbox" "--sandbox" "$out"
assert_none "agy review no --project flag" " --project " "$out"
assert_one "agy review add-dir RUN" "--add-dir $RUN" "$out"
assert_one "agy review print-timeout" "--print-timeout 15m" "$out"
assert_one "agy review disable-slash" "--disable-slash-commands" "$out"
assert_one "agy review output stream-json" "--output-format stream-json" "$out"
assert_one "agy review effort high" "--effort high" "$out"
assert_none "agy review unpinned no --model" "--model " "$out"
[[ "$out" == *"-p \"\$(cat $RUN/brief.md)\""* ]] && ok "agy review -p cat brief" \
  || fail_msg "agy review -p cat brief ($out)"

expect_ok "dry-run agy implement" \
  --backend agy --mode implement --project "$ROOT" --run "$RUN" --dry-run
assert_one "agy implement skip-permissions" "--dangerously-skip-permissions" "$out"
assert_one "agy implement mode accept-edits" "--mode accept-edits" "$out"
assert_none "agy implement no sandbox" "--sandbox" "$out"
assert_none "agy implement no add-dir" "--add-dir" "$out"

expect_ok "dry-run agy maps xhigh effort" \
  --backend agy --project "$ROOT" --run "$RUN" --effort xhigh --dry-run
assert_one "agy xhigh becomes high" "--effort high" "$out"
assert_none "agy xhigh not forwarded" "--effort xhigh" "$out"

expect_ok "dry-run agy pinned model" \
  --backend agy --project "$ROOT" --run "$RUN" --model gemini-3.7-flash-high --dry-run
assert_one "agy pinned model" "--model gemini-3.7-flash-high" "$out"

expect_die "gemini is not a spawn backend" "backend must be" \
  --backend gemini --project "$ROOT" --run "$RUN" --dry-run

expect_ok "dry-run passes --model and --effort" \
  --backend claude --project "$ROOT" --run "$RUN" --model sonnet --effort high --dry-run
assert_one "model sonnet" "--model sonnet" "$out"
assert_one "effort high" "--effort high" "$out"
assert_one "model/effort one permission-mode" "--permission-mode" "$out"

expect_ok "dry-run claude unpinned policy default opus" \
  --backend claude --project "$ROOT" --run "$RUN" --dry-run
assert_one "claude default opus" "--model opus" "$out"

expect_ok "dry-run claude version-pin fable 5.1" \
  --backend claude --project "$ROOT" --run "$RUN" --model claude-fable-5-1 --dry-run
assert_one "claude-fable-5-1" "--model claude-fable-5-1" "$out"

expect_die "bracketed model alias rejected" "invalid --model" \
  --backend claude --project "$ROOT" --run "$RUN" --model 'fable[1m]' --dry-run

expect_ok "dry-run codex --effort in -c" \
  --backend codex --project "$ROOT" --run "$RUN" --model gpt-5.6-sol --effort xhigh --dry-run
assert_one "codex model" "-m gpt-5.6-sol" "$out"
assert_one "codex effort -c" "-c model_reasoning_effort=xhigh" "$out"
assert_one "codex default-mode review approve-for-me" "--approve-for-me" "$out"
assert_none "codex default-mode review no sandbox" "--sandbox" "$out"

expect_ok "dry-run codex unpinned policy default sol" \
  --backend codex --project "$ROOT" --run "$RUN" --dry-run
assert_one "codex default sol" "-m gpt-5.6-sol" "$out"

expect_ok "dry-run codex optional astra" \
  --backend codex --project "$ROOT" --run "$RUN" --model gpt-6-astra --dry-run
assert_one "codex astra" "-m gpt-6-astra" "$out"

# --- live PATH stubs (fail closed if stubs missing) ---

mkwork
STUBDIR="$LAST_TMP"
export HS_STUB_DIR="$STUBDIR"

write_stub_common() {
  local name="$1"
  cat >"$STUBDIR/$name" <<'EOF'
#!/bin/bash
set -euo pipefail
: "${HS_STUB_DIR:?}"
me="$(basename "$0")"
printf '%s\n' "$@" >"$HS_STUB_DIR/$me.argv"
printf '%s\n' "${HARNESS_SUBAGENT_RUN-}" >"$HS_STUB_DIR/$me.runenv"
printf '%s\n' "${CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH-}" >"$HS_STUB_DIR/$me.depthenv"
cat >"$HS_STUB_DIR/$me.stdin"
EOF
}

write_stub_common claude
printf '%s\n' 'echo CLAUDE_MARKER' >>"$STUBDIR/claude"

write_stub_common grok
cat >>"$STUBDIR/grok" <<'EOF'
prompt=""
args=("$@")
i=0
while ((i < ${#args[@]})); do
  if [[ "${args[i]}" == "--prompt-file" ]]; then
    prompt="${args[i+1]-}"
    break
  fi
  i=$((i + 1))
done
[[ -n "$prompt" && -s "$prompt" ]]
echo GROK_MARKER
EOF

cat >"$STUBDIR/codex" <<'EOF'
#!/bin/bash
set -euo pipefail
: "${HS_STUB_DIR:?}"
printf '%s\n' "$@" >"$HS_STUB_DIR/codex.argv"
cat >"$HS_STUB_DIR/codex.stdin"
out=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-o" ]]; then
    out="${2-}"
    shift 2
    continue
  fi
  shift
done
[[ -n "$out" ]]
echo CODEX_MARKER >"$out"
printf '%s\n' '{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}'
EOF

write_stub_common agy
cat >>"$STUBDIR/agy" <<'EOF'
printf '%s\n' '{"type":"init","conversation_id":"22222222-2222-4222-8222-222222222222"}' '{"type":"result","result":{"response":"AGY_MARKER"}}'
EOF

chmod +x "$STUBDIR/claude" "$STUBDIR/codex" "$STUBDIR/grok" "$STUBDIR/agy"

ORIG_PATH="$PATH"
isolated_bin() {
  local name="$1" found
  found="$(PATH="$STUBDIR:$ORIG_PATH" command -v "$name" || true)"
  if [[ "$found" == "$STUBDIR/$name" ]]; then
    ok "command -v $name is the stub"
  else
    fail_msg "command -v $name not isolated (got=${found:-empty})"
    return 1
  fi
}

isolated_bin claude
isolated_bin codex
isolated_bin grok
isolated_bin agy

run_isolated() {
  local outf errf
  outf="$(mktemp "${TMPDIR:-/tmp}/hs-out.XXXXXX")"
  errf="$(mktemp "${TMPDIR:-/tmp}/hs-err.XXXXXX")"
  WORK+=("$outf" "$errf")
  set +e
  PATH="$STUBDIR:$ORIG_PATH" "$BASH_BIN" "$SPAWN" "$@" >"$outf" 2>"$errf"
  ec=$?
  set -e
  out="$(cat "$outf")"
  err="$(cat "$errf")"
}

brief_eq() {
  local got="$1" expected="$2" desc="$3"
  if cmp -s "$got" "$expected"; then
    ok "$desc"
  else
    fail_msg "$desc"
  fi
}

make_run
CRUN="$LAST_TMP"
run_isolated --backend claude --mode review --project "$ROOT" --run "$CRUN"
if [[ "$ec" -eq 0 && "$(cat "$CRUN/last.md")" == "CLAUDE_MARKER" && -f "$CRUN/stderr.log" ]]; then
  ok "claude live last.md + stderr.log"
else
  fail_msg "claude live last.md (exit=$ec last=$(cat "$CRUN/last.md" 2>/dev/null || true) log=$(cat "$CRUN/stderr.log" 2>/dev/null || true))"
fi
brief_eq "$STUBDIR/claude.stdin" "$CRUN/brief.md" "claude consumed brief on stdin"
if [[ "$(cat "$STUBDIR/claude.runenv")" == "$CRUN" ]]; then
  ok "child sees HARNESS_SUBAGENT_RUN"
else
  fail_msg "child HARNESS_SUBAGENT_RUN (got=$(cat "$STUBDIR/claude.runenv" 2>/dev/null || true) want=$CRUN)"
fi
if [[ "$(cat "$STUBDIR/claude.depthenv")" == "1" ]]; then
  ok "child CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1"
else
  fail_msg "child spawn depth (got=$(cat "$STUBDIR/claude.depthenv" 2>/dev/null || true))"
fi

cat >"$STUBDIR/claude" <<'EOF'
#!/bin/bash
set -euo pipefail
: "${HS_STUB_DIR:?}"
printf '%s\n' "$@" >"$HS_STUB_DIR/claude.argv"
cat >"$HS_STUB_DIR/claude.stdin"
printf '%s\n' 'Using skill…' '' 'VERDICT — done.' 'body'
EOF
chmod +x "$STUBDIR/claude"

make_run
PRUN="$LAST_TMP"
run_isolated --backend claude --mode review --project "$ROOT" --run "$PRUN"
first="$(head -n 1 "$PRUN/last.md")"
if [[ "$ec" -eq 0 && "$first" == "VERDICT — done." ]]; then
  ok "claude last.md stripped to VERDICT"
else
  fail_msg "claude VERDICT strip (exit=$ec first=$first)"
fi

cat >"$STUBDIR/claude" <<'EOF'
#!/bin/bash
set -euo pipefail
: "${HS_STUB_DIR:?}"
printf '%s\n' "$@" >"$HS_STUB_DIR/claude.argv"
cat >/dev/null
printf '%s\n' 'VERDICT — done.'
EOF
chmod +x "$STUBDIR/claude"
make_run
QRUN="$LAST_TMP"
run_isolated --backend claude --mode review --project "$ROOT" --run "$QRUN"
if [[ "$(cat "$QRUN/last.md")" == "VERDICT — done." ]]; then
  ok "claude last.md already VERDICT first"
else
  fail_msg "claude already VERDICT ($(cat "$QRUN/last.md"))"
fi

cat >"$STUBDIR/claude" <<'EOF'
#!/bin/bash
set -euo pipefail
cat >/dev/null
printf '%s\n' 'no verdict in this report'
EOF
chmod +x "$STUBDIR/claude"
make_run
NRUN="$LAST_TMP"
run_isolated --backend claude --mode review --project "$ROOT" --run "$NRUN"
if [[ "$(cat "$NRUN/last.md")" == "no verdict in this report" ]]; then
  ok "claude last.md unchanged without VERDICT"
else
  fail_msg "claude no-VERDICT mutated"
fi
if [[ "$(cat "$NRUN/capture-status.txt")" == "no-verdict" ]]; then
  ok "claude capture-status no-verdict"
else
  fail_msg "claude capture-status ($(cat "$NRUN/capture-status.txt" 2>/dev/null || true))"
fi

# report.md wins over cleanup stdout
cat >"$STUBDIR/claude" <<'EOF'
#!/bin/bash
set -euo pipefail
: "${HS_STUB_DIR:?}"
run_dir=""
prev=""
for a in "$@"; do
  if [[ "$prev" == "--add-dir" ]]; then run_dir="$a"; fi
  prev="$a"
done
cat >/dev/null
printf '%s\n' 'VERDICT — from report.' 'FINDINGS — none.' >"$run_dir/report.md"
printf '%s\n' 'Background find finished — leftover screenshots deleted.'
EOF
chmod +x "$STUBDIR/claude"
make_run
RRUN="$LAST_TMP"
run_isolated --backend claude --mode review --project "$ROOT" --run "$RRUN"
if [[ "$(head -n 1 "$RRUN/last.md")" == "VERDICT — from report." && "$(cat "$RRUN/capture-status.txt")" == "ok-report" ]]; then
  ok "claude prefers report.md over cleanup stdout"
else
  fail_msg "claude report.md prefer (last=$(head -c 200 "$RRUN/last.md" 2>/dev/null || true) status=$(cat "$RRUN/capture-status.txt" 2>/dev/null || true))"
fi

# markdown-bold VERDICT unwrap
cat >"$STUBDIR/claude" <<'EOF'
#!/bin/bash
set -euo pipefail
cat >/dev/null
printf '%s\n' '**VERDICT — bold ok**' 'body'
EOF
chmod +x "$STUBDIR/claude"
make_run
BRUN="$LAST_TMP"
run_isolated --backend claude --mode review --project "$ROOT" --run "$BRUN"
first="$(head -n 1 "$BRUN/last.md")"
if [[ "$first" == "VERDICT — bold ok" ]]; then
  ok "claude unwraps bold VERDICT"
else
  fail_msg "claude bold VERDICT ($first)"
fi

# usage limit → BLOCKED VERDICT
cat >"$STUBDIR/claude" <<'EOF'
#!/bin/bash
set -euo pipefail
cat >/dev/null
printf '%s\n' "You've hit your session limit · resets 11:30am (Europe/Vienna)"
exit 1
EOF
chmod +x "$STUBDIR/claude"
make_run
URUN="$LAST_TMP"
run_isolated --backend claude --mode review --project "$ROOT" --run "$URUN"
if [[ "$ec" -eq 1 && -f "$URUN/last.md" && -f "$URUN/capture-status.txt" ]] \
  && [[ "$(head -n 1 "$URUN/last.md")" == 'VERDICT — BLOCKED: usage/rate limit' ]] \
  && grep -qx 'usage-limit' "$URUN/capture-status.txt"; then
  ok 'claude exit-1 usage-limit preserves status and blocked capture'
else
  fail_msg "claude exit-1 usage-limit capture (exit=$ec)"
fi

make_run
XRUN="$LAST_TMP"
run_isolated --backend grok --mode review --project "$ROOT" --run "$XRUN"
if [[ "$ec" -eq 0 && "$(cat "$XRUN/last.md")" == "GROK_MARKER" && -f "$XRUN/stderr.log" ]]; then
  ok "grok live last.md + stderr.log"
else
  fail_msg "grok live last.md (exit=$ec last=$(cat "$XRUN/last.md" 2>/dev/null || true))"
fi
if [[ ! -s "$STUBDIR/grok.stdin" ]]; then
  ok "grok stdin empty"
else
  fail_msg "grok stdin not empty"
fi
if grep -qx -- "--prompt-file" "$STUBDIR/grok.argv" \
  && grep -qx -- "$XRUN/brief.md" "$STUBDIR/grok.argv"; then
  ok "grok argv --prompt-file is brief.md"
else
  fail_msg "grok argv --prompt-file ($(cat "$STUBDIR/grok.argv"))"
fi

make_run
DRUN="$LAST_TMP"
run_isolated --backend codex --mode review --project "$ROOT" --run "$DRUN"
if [[ "$ec" -eq 0 && "$(cat "$DRUN/last.md")" == "CODEX_MARKER" && -f "$DRUN/stderr.log" ]]; then
  ok "codex live last.md via -o + stderr.log"
else
  fail_msg "codex live last.md (exit=$ec last=$(cat "$DRUN/last.md" 2>/dev/null || true) err=$err)"
fi
brief_eq "$STUBDIR/codex.stdin" "$DRUN/brief.md" "codex consumed brief on stdin"

make_run
ARUN="$LAST_TMP"
run_isolated --backend agy --mode review --project "$ROOT" --run "$ARUN"
if [[ "$ec" -eq 0 && "$(cat "$ARUN/last.md")" == "AGY_MARKER" && -f "$ARUN/stderr.log" ]]; then
  ok "agy live last.md + stderr.log"
else
  fail_msg "agy live last.md (exit=$ec last=$(cat "$ARUN/last.md" 2>/dev/null || true) err=$err)"
fi
if [[ ! -s "$STUBDIR/agy.stdin" ]]; then
  ok "agy stdin empty"
else
  fail_msg "agy stdin not empty"
fi
if grep -qx -- "-p" "$STUBDIR/agy.argv" \
  && grep -qx -- "$(cat "$ARUN/brief.md")" "$STUBDIR/agy.argv"; then
  ok "agy argv -p is brief.md contents"
else
  fail_msg "agy argv -p ($(cat "$STUBDIR/agy.argv"))"
fi
if grep -qx -- "--dangerously-skip-permissions" "$STUBDIR/agy.argv"; then
  fail_msg "agy review passed skip-permissions"
else
  ok "agy review omitted skip-permissions"
fi

capture_case() {
  local label="$1" expected_status="$5" expected_first="$6"
  local backend="${9:-claude}"
  export HS_CAPTURE_OUT="$2" HS_CAPTURE_ERR="$3" HS_CAPTURE_EC="$4"
  export HS_CAPTURE_REPORT="${7-}" HS_CAPTURE_OMIT="${10:-0}"
  make_run
  CAPRUN="$LAST_TMP"
  if [[ -n "${8-}" ]]; then printf '%s' "$8" >"$CAPRUN/last.md"; fi
  cat >"$STUBDIR/$backend" <<'EOF'
#!/bin/bash
set -euo pipefail
cat >/dev/null
target=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == '-o' ]]; then target="$2"; shift 2; else shift; fi
done
if [[ -n "$HS_CAPTURE_REPORT" ]]; then
  printf '%s' "$HS_CAPTURE_REPORT" >"$HARNESS_SUBAGENT_RUN/report.md"
fi
if [[ -n "$target" ]]; then
  if [[ "$HS_CAPTURE_OMIT" == 0 ]]; then printf '%s' "$HS_CAPTURE_OUT" >"$target"; fi
else
  printf '%s' "$HS_CAPTURE_OUT"
fi
printf '%s' "$HS_CAPTURE_ERR" >&2
exit "$HS_CAPTURE_EC"
EOF
  chmod +x "$STUBDIR/$backend"
  run_isolated --backend "$backend" --mode review --project "$ROOT" --run "$CAPRUN"
  if [[ "$ec" -eq "$HS_CAPTURE_EC" && -f "$CAPRUN/last.md" ]] \
    && [[ -f "$CAPRUN/capture-status.txt" ]] \
    && grep -qx "$expected_status" "$CAPRUN/capture-status.txt" \
    && [[ "$(head -n 1 "$CAPRUN/last.md")" == "$expected_first" ]]; then
    ok "$label"
  else
    fail_msg "$label (exit=$ec)"
  fi
  if [[ "$HS_CAPTURE_OMIT" == 0 ]]; then
    if cmp -s "$CAPRUN/stdout.md" <(printf '%s' "$HS_CAPTURE_OUT"); then
      ok "$label raw stdout preserved"
    else fail_msg "$label raw stdout changed"; fi
  fi
  if cmp -s "$CAPRUN/stderr.log" <(printf '%s' "$HS_CAPTURE_ERR"); then
    ok "$label raw stderr preserved"
  else fail_msg "$label raw stderr changed"; fi
  if [[ -n "$HS_CAPTURE_REPORT" ]]; then
    if cmp -s "$CAPRUN/report.md" <(printf '%s' "$HS_CAPTURE_REPORT"); then
      ok "$label durable report preserved"
    else fail_msg "$label durable report changed"; fi
  fi
}

for backend in claude codex grok agy; do
  capture_case "$backend generic exit 7" '' 'fatal: connection refused' 7 \
    no-verdict '' '' '' "$backend"
done
capture_case 'empty exit 1' '' '' 1 no-verdict ''
capture_case 'empty success' '' '' 0 no-verdict ''
capture_case 'report plus exit 7' 'cleanup chatter' '' 7 ok-report \
  'VERDICT — from report.' $'VERDICT — from report.\nFINDINGS — none.\n'

blocked='VERDICT — BLOCKED: usage/rate limit'
session="You've hit your session limit · resets 11:30am (Europe/Vienna)"
capture_case 'stderr-only session limit' '' "$session" 1 usage-limit "$blocked"
if grep -Fq 'stderr.log' "$CAPRUN/last.md" \
  && grep -Fq "$session" "$CAPRUN/last.md"; then
  ok 'stderr source and reset evidence retained'
else fail_msg 'stderr source or reset evidence missing'; fi

capture_case 'missing Codex output file' '' "$session" 1 usage-limit "$blocked" \
  '' '' codex 1
if [[ ! -e "$CAPRUN/stdout.md" ]]; then ok 'Codex output remains missing';
else fail_msg 'raw Codex output unexpectedly created'; fi

capture_case 'stderr limit with ordinary stdout' 'partial progress' "$session" \
  1 usage-limit "$blocked"
capture_case 'stdout session evidence' "$session" '' 1 usage-limit "$blocked"
if grep -Fq 'stdout.md' "$CAPRUN/last.md" \
  && grep -Fq "$session" "$CAPRUN/last.md"; then
  ok 'stdout source and reset evidence retained'
else fail_msg 'stdout source or reset evidence missing'; fi

capture_case 'selected last fallback' '' '' 1 usage-limit "$blocked" '' "$session"
capture_case 'report verdict wins over both limit streams' "$session" "$session" \
  7 ok-report 'VERDICT — from report.' $'VERDICT — from report.\n'
capture_case 'stdout verdict wins over incidental stderr' \
  $'preamble\nVERDICT: done\nbody\n' "$session" 0 ok 'VERDICT: done'
capture_case 'bold verdict normalization remains intact' \
  $'**VERDICT — done**\nbody\n' "$session" 0 ok 'VERDICT — done'
capture_case 'non-verdict report does not outrank stdout' \
  'VERDICT — stdout.' '' 0 ok 'VERDICT — stdout.' 'draft without verdict'
capture_case 'empty missing Codex output still finalizes' '' '' 7 no-verdict '' \
  '' '' codex 1

blocked='VERDICT — BLOCKED: usage/rate limit'
for diagnostic in \
  'HTTP 429; Retry-After: 30' \
  'Error 429: retry in 20 seconds' \
  'tOo MaNy ReQuEsTs; retry in 10 seconds' \
  'Quota exhausted' 'Exceeded quota' 'quota has been exceeded' \
  'Insufficient credits' 'Credits exhausted' \
  'Spend limit reached' 'Spending limit exceeded' \
  'HTTP 429: insufficient credits'; do
  for stream in stdout stderr; do
    fixture_out='' fixture_err=''
    if [[ "$stream" == stdout ]]; then fixture_out="$diagnostic";
    else fixture_err="$diagnostic"; fi
    capture_case "$stream: $diagnostic" "$fixture_out" "$fixture_err" \
      1 usage-limit "$blocked"
    if grep -Fq "$diagnostic" "$CAPRUN/last.md"; then
      ok "$stream diagnostic retained"
    else fail_msg "$stream diagnostic lost"; fi
  done
done
for prose in 'We should document quota and credits.' \
  'Quota remaining: 50; credits available: 10.' \
  'Processed 429 items successfully.'; do
  capture_case 'benign stdout' "$prose" '' 1 no-verdict "$prose"
  capture_case 'benign stderr' '' "$prose" 1 no-verdict ''
done
capture_case 'exit 1 alone is not a limit' '' '' 1 no-verdict ''
capture_case 'limit is evidence-based even at exit 0' \
  'HTTP 429' '' 0 usage-limit "$blocked"
capture_case 'credits evidence alongside generic 429' 'HTTP 429' \
  'Insufficient credits' 1 usage-limit "$blocked"
if grep -Fq 'HTTP 429' "$CAPRUN/last.md" \
  && grep -Fq 'Insufficient credits' "$CAPRUN/last.md" \
  && grep -Fq 'stdout.md' "$CAPRUN/last.md" \
  && grep -Fq 'stderr.log' "$CAPRUN/last.md"; then
  ok 'both sources retained for parent precedence decision'
else fail_msg 'combined rate and spend evidence incomplete'; fi

# Persistent identity and structured capture use Python 3, like spawn's consumer.
PYTHON=""
for candidate in python python3; do
  if command -v "$candidate" >/dev/null && "$candidate" -c 'import sys; assert sys.version_info.major == 3' 2>/dev/null; then
    PYTHON="$candidate"; break
  fi
done
[[ -n "$PYTHON" ]] || { fail_msg 'Python 3 required for identity fixtures'; exit 1; }
SID_A=11111111-1111-4111-8111-111111111111
SID_B=22222222-2222-4222-8222-222222222222

identity_ok() {
  "$PYTHON" - "$1" "$2" "$3" "$ROOT" <<'PY'
import json, pathlib, sys, uuid
run, backend, preassigned, project = sys.argv[1:]
p = pathlib.Path(run)
raw = (p / 'session-id').read_bytes()
sid = raw.decode().removesuffix('\n')
assert raw == (str(uuid.UUID(sid)) + '\n').encode()
d = json.loads((p / 'session.json').read_text())
key = {'claude':'session_id','grok':'session_id','codex':'thread_id','agy':'conversation_id'}[backend]
assert d['backend'] == backend and d['native_key'] == key
assert d['id'] == sid == d[key]
assert pathlib.Path(d['cwd']).resolve() == pathlib.Path(project).resolve()
assert pathlib.Path(d['origin_run']).resolve() == p.resolve()
assert pathlib.Path(d['attempt_run']).resolve() == p.resolve()
assert d['preassigned'] == (preassigned == 'true')
assert all(k in d for k in ('model', 'effort', 'mode', 'persistence_available'))
PY
}

for pair in "claude:$CRUN:true" "grok:$XRUN:true" "codex:$DRUN:false" "agy:$ARUN:false"; do
  IFS=: read -r backend identity_run assigned <<<"$pair"
  if identity_ok "$identity_run" "$backend" "$assigned"; then ok "$backend identity binding";
  else fail_msg "$backend identity binding"; fi
done

# One stub protocol for structured event fixtures; it also records actual argv.
write_event_stub() {
  cat >"$STUBDIR/$1" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$@" >"$HS_STUB_DIR/event.argv"
printf launched >"$HS_STUB_DIR/launched"
cat >"$HS_STUB_DIR/event.stdin"
target=''
while [[ $# -gt 0 ]]; do
  if [[ "$1" == -o ]]; then target="$2"; shift 2; else shift; fi
done
if [[ -n "$target" ]]; then printf '%s' "$HS_EVENT_TEXT" >"$target"; fi
if [[ -n "${HS_EVENTS_FILE-}" ]]; then cat "$HS_EVENTS_FILE"; else printf '%s' "$HS_EVENTS"; fi
printf '%s' "${HS_EVENT_ERR-}" >&2
exit "$HS_EVENT_EC"
EOF
  chmod +x "$STUBDIR/$1"
}
event_case() {
  local backend="$1"
  unset HS_EVENTS_FILE
  export HS_EVENTS="$2" HS_EVENT_TEXT="${4-}" HS_EVENT_EC="$3"
  write_event_stub "$backend"
  make_run; EVENTRUN="$LAST_TMP"
  run_isolated --backend "$backend" --project "$ROOT" --run "$EVENTRUN"
}

for backend in codex agy; do
  if [[ "$backend" == codex ]]; then init="{\"type\":\"thread.started\",\"thread_id\":\"$SID_A\"}";
  else init="{\"type\":\"init\",\"conversation_id\":\"$SID_A\"}"; fi
  event_case "$backend" "$init" 1
  if [[ "$ec" == 1 && -f "$EVENTRUN/last.md" && -f "$EVENTRUN/capture-status.txt" ]] \
    && identity_ok "$EVENTRUN" "$backend" false && [[ "$(cat "$EVENTRUN/session-id")" == "$SID_A" ]]; then
    ok "$backend early ID survives exit 1 with finalized capture"
  else fail_msg "$backend early ID exit 1 (exit=$ec)"; fi
done

event_case agy $'{"type":"text_delta","text":"VERDICT: "}\n{"type":"text_delta","text":"done"}\n' 0
[[ "$ec" == 0 && "$(cat "$EVENTRUN/last.md")" == 'VERDICT: done' ]] && ok 'agy concatenates human deltas' || fail_msg 'agy delta extraction'
event_case agy $'{"type":"text_delta","text":"draft"}\n{"type":"result","result":{"response":"VERDICT: final"}}\n' 0
[[ "$ec" == 0 && "$(cat "$EVENTRUN/last.md")" == 'VERDICT: final' ]] && ok 'agy final response outranks deltas' || fail_msg 'agy result extraction'
event_case agy '{"type":"init","conversation_id":""}' 0
[[ "$ec" == 0 && ! -e "$EVENTRUN/session-id" ]] && ok 'empty agy ID unavailable' || fail_msg 'empty agy ID published'
for backend in codex agy; do
  event_case "$backend" '{"type":"error","message":"HTTP 429; Retry-After: 30"}' 1
  if [[ "$ec" == 1 ]] && grep -qx usage-limit "$EVENTRUN/capture-status.txt" \
    && grep -Fq 'provider-errors' "$EVENTRUN/last.md" && grep -Fq 'Retry-After: 30' "$EVENTRUN/last.md"; then
    ok "$backend decoded provider error evidence"
  else fail_msg "$backend provider error capture"; fi
  event_case "$backend" '{"type":"tool_result","content":"HTTP 429"}' 0
  [[ "$ec" == 0 && "$(cat "$EVENTRUN/capture-status.txt")" == no-verdict ]] && ok "$backend tool payload is not error evidence" || fail_msg "$backend tool payload misclassified"
  event_case "$backend" 'not JSON' 0
  if [[ "$ec" != 0 && -f "$EVENTRUN/capture-status.txt" ]] && grep -q '^VERDICT.*BLOCKED' "$EVENTRUN/last.md"; then
    ok "$backend parser failure finalizes and fails visibly"
  else fail_msg "$backend parser failure hidden (exit=$ec)"; fi
  # Production change this catches: blocked_capture after JSONL parse failure
  # overwriting an already-classified usage-limit last.md / capture-status.
  event_case "$backend" $'{"type":"error","message":"HTTP 429; Retry-After: 30"}\nnot JSON\n' 1
  if [[ "$ec" == 1 ]] && grep -qx usage-limit "$EVENTRUN/capture-status.txt" \
    && [[ "$(head -n 1 "$EVENTRUN/last.md")" == 'VERDICT — BLOCKED: usage/rate limit' ]] \
    && grep -Fq 'Retry-After: 30' "$EVENTRUN/last.md" \
    && grep -Fq 'provider-errors' "$EVENTRUN/last.md"; then
    ok "$backend parser failure does not hide usage-limit"
  else fail_msg "$backend parser failure hid usage-limit (exit=$ec status=$(cat "$EVENTRUN/capture-status.txt" 2>/dev/null || true) first=$(head -n 1 "$EVENTRUN/last.md" 2>/dev/null || true))"; fi
  # Production change this catches: session_data events 2>>"$ERR" appending
  # parser diagnostics onto the provider stderr artifact.
  export HS_EVENT_ERR='PROVIDER_STDERR_UNIQUE'
  event_case "$backend" 'not JSON' 0
  if [[ "$ec" != 0 ]] && grep -q '^VERDICT.*BLOCKED' "$EVENTRUN/last.md" \
    && cmp -s "$EVENTRUN/stderr.log" <(printf '%s' "$HS_EVENT_ERR"); then
    ok "$backend parser failure leaves provider stderr unchanged"
  else fail_msg "$backend parser failure mutated stderr (exit=$ec stderr=$(cat "$EVENTRUN/stderr.log" 2>/dev/null | tr '\n' '|' || true))"; fi
  unset HS_EVENT_ERR
done

# Production change this catches: `if parse_error is not None: continue` skipping
# independently valid later provider-error records, so a 429 after `not JSON`
# never reaches provider-errors.log / usage-limit classification.
for backend in codex agy; do
  if [[ "$backend" == codex ]]; then init="{\"type\":\"thread.started\",\"thread_id\":\"$SID_A\"}";
  else init="{\"type\":\"init\",\"conversation_id\":\"$SID_A\"}"; fi
  event_case "$backend" "${init}"$'\nnot JSON\n{"type":"error","message":"HTTP 429; Retry-After: 30"}\n' 1
  if [[ "$ec" == 1 ]] && grep -qx usage-limit "$EVENTRUN/capture-status.txt" \
    && [[ "$(head -n 1 "$EVENTRUN/last.md")" == 'VERDICT — BLOCKED: usage/rate limit' ]] \
    && grep -Fq 'Retry-After: 30' "$EVENTRUN/last.md" \
    && grep -Fq 'provider-errors' "$EVENTRUN/last.md" \
    && identity_ok "$EVENTRUN" "$backend" false \
    && cmp -s "$EVENTRUN/events.jsonl" <(printf '%s' "$HS_EVENTS"); then
    ok "$backend later 429 after malformed line still classifies usage-limit"
  else
    fail_msg "$backend later 429 after malformed line (exit=$ec status=$(cat "$EVENTRUN/capture-status.txt" 2>/dev/null || true) first=$(head -n 1 "$EVENTRUN/last.md" 2>/dev/null || true))"
  fi
  event_case "$backend" "${init}"$'\nnot JSON\n{"type":"tool_result","content":"HTTP 429; Retry-After: 30"}\n' 1
  if [[ "$ec" == 1 ]] && ! grep -qx usage-limit "$EVENTRUN/capture-status.txt" 2>/dev/null \
    && grep -q '^VERDICT.*BLOCKED' "$EVENTRUN/last.md" \
    && cmp -s "$EVENTRUN/events.jsonl" <(printf '%s' "$HS_EVENTS"); then
    ok "$backend later tool payload after malformed line is not limit evidence"
  else
    fail_msg "$backend later tool payload after malformed line (exit=$ec status=$(cat "$EVENTRUN/capture-status.txt" 2>/dev/null || true))"
  fi
done

# Production change this catches: session_data events iterating text-mode
# sys.stdin (locale cp1252), so UTF-8 Ł (C5 81, undefined in cp1252) aborts the
# drain, and universal newlines collapse provider CRLF before events.jsonl.
# Do not rely on PYTHONUTF8=1; force a cp1252 stdin encoding for the fixture.
for backend in codex agy; do
  mkwork
  utf8_jsonl="$LAST_TMP/utf8-crlf.jsonl"
  "$PYTHON" - "$backend" "$SID_A" "$utf8_jsonl" <<'PY'
import json, pathlib, sys
backend, sid, dest = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
if backend == 'codex':
    init = {'type': 'thread.started', 'thread_id': sid}
else:
    init = {'type': 'init', 'conversation_id': sid}
err = {
    'type': 'error',
    'message': 'VERDICT \u2014 \u0141 \U0001f600 HTTP 429; Retry-After: 30',
}
payload = (
    json.dumps(init, ensure_ascii=False).encode('utf-8') + b'\r\n'
    + json.dumps(err, ensure_ascii=False).encode('utf-8') + b'\r\n'
)
assert b'\xc5\x81' in payload
assert b'\xe2\x80\x94' in payload
assert b'\xf0\x9f\x98\x80' in payload
assert payload.count(b'\r\n') == 2
dest.write_bytes(payload)
PY
  export HS_EVENTS_FILE="$utf8_jsonl" HS_EVENTS='' HS_EVENT_TEXT='' HS_EVENT_EC=1
  write_event_stub "$backend"
  make_run; EVENTRUN="$LAST_TMP"
  PYTHONUTF8=0 PYTHONIOENCODING=cp1252 run_isolated --backend "$backend" --project "$ROOT" --run "$EVENTRUN"
  if [[ "$ec" == 1 ]] && grep -qx usage-limit "$EVENTRUN/capture-status.txt" \
    && [[ "$(head -n 1 "$EVENTRUN/last.md")" == 'VERDICT — BLOCKED: usage/rate limit' ]] \
    && grep -Fq 'Retry-After: 30' "$EVENTRUN/last.md" \
    && grep -Fq 'provider-errors' "$EVENTRUN/last.md" \
    && cmp -s "$EVENTRUN/events.jsonl" "$utf8_jsonl" \
    && "$PYTHON" - "$EVENTRUN/events.jsonl" "$utf8_jsonl" "$EVENTRUN/provider-errors.log" <<'PY'
import pathlib, sys
events, src, errors = map(pathlib.Path, sys.argv[1:])
raw = events.read_bytes()
assert raw == src.read_bytes()
assert b'\r\n' in raw and raw.count(b'\r\n') == 2
assert b'\xc5\x81' in raw
err = errors.read_bytes()
assert b'\xc5\x81' in err
assert b'\xe2\x80\x94' in err
assert b'\xf0\x9f\x98\x80' in err
assert b'Retry-After: 30' in err
PY
  then
    ok "$backend UTF-8 JSONL and CRLF survive cp1252 stdin"
  else
    fail_msg "$backend UTF-8/CRLF capture (exit=$ec status=$(cat "$EVENTRUN/capture-status.txt" 2>/dev/null || true) first=$(head -n 1 "$EVENTRUN/last.md" 2>/dev/null || true))"
  fi
  unset HS_EVENTS_FILE
done

# Production change this catches: agy stdout.md written only after parse+resume
# checks succeed, dropping decoded human text when a later line is malformed.
limit_text='HTTP 429; Retry-After: 30'
event_case agy "{\"type\":\"text_delta\",\"text\":\"$limit_text\"}"$'\nnot JSON\n' 1
if [[ "$ec" == 1 ]] && grep -qx usage-limit "$EVENTRUN/capture-status.txt" \
  && [[ -s "$EVENTRUN/stdout.md" ]] && grep -Fq "$limit_text" "$EVENTRUN/stdout.md" \
  && grep -Fq "$limit_text" "$EVENTRUN/last.md"; then
  ok 'agy valid text then parser failure still classifies decoded limit'
else fail_msg "agy text-then-parse-failure lost decoded limit (exit=$ec status=$(cat "$EVENTRUN/capture-status.txt" 2>/dev/null || true) stdout=$(head -c 120 "$EVENTRUN/stdout.md" 2>/dev/null || true))"; fi

for backend in claude grok; do
  cat >"$STUBDIR/$backend" <<'EOF'
#!/bin/bash
set -euo pipefail
cat >/dev/null
sid=''
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --session-id ]]; then sid="$2"; shift 2; else shift; fi
done
[[ -n "$sid" && "$(cat "$HARNESS_SUBAGENT_RUN/session-id")" == "$sid" && -s "$HARNESS_SUBAGENT_RUN/session.json" ]] || exit 9
printf 'VERDICT: preassigned before launch\n'
EOF
  chmod +x "$STUBDIR/$backend"
  make_run; PREASSIGNED_RUN="$LAST_TMP"
  run_isolated --backend "$backend" --project "$ROOT" --run "$PREASSIGNED_RUN"
  [[ "$ec" == 0 ]] && ok "$backend ID exists before launch" || fail_msg "$backend preassignment (exit=$ec)"
done
make_run; SKIPRUN="$LAST_TMP"
CLAUDE_CODE_SKIP_PROMPT_HISTORY=1 run_isolated --backend claude --project "$ROOT" --run "$SKIPRUN"
if [[ "$ec" == 0 ]] && "$PYTHON" - "$SKIPRUN/session.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d['persistence_available'] is False
assert 'CLAUDE_CODE_SKIP_PROMPT_HISTORY' in d['unavailable_reason']
PY
then ok 'Claude disabled history recorded without overriding'; else fail_msg 'Claude persistence opt-out lost'; fi

# S2: parent copies only identity records into a separate continuation attempt.
make_attempt() {
  make_run; ATTEMPT="$LAST_TMP"
  cp "$1/session-id" "$1/session.json" "$ATTEMPT/"
  printf 'Continue unfinished work; read checkpoint at %s/report.md; write this attempt report. Worker: do not spawn.\n' "$1" >"$ATTEMPT/brief.md"
  RESUME_SID="$(cat "$ATTEMPT/session-id")"
}
for backend in claude codex grok agy; do
  case "$backend" in claude) origin="$CRUN";; codex) origin="$DRUN";; grok) origin="$XRUN";; agy) origin="$ARUN";; esac
  make_attempt "$origin"
  before="$(cat "$ATTEMPT/session.json")"
  expect_ok "$backend exact resume dry-run" --backend "$backend" --project "$ROOT" --run "$ATTEMPT" --resume-id "$RESUME_SID" --dry-run
  case "$backend" in
    claude|grok) assert_one "$backend exact resume selector" "--resume $RESUME_SID" "$out";;
    codex)
      assert_one 'codex resume grammar exec flags before subcommand' "exec --approve-for-me -C $ROOT resume -m gpt-5.6-sol" "$out"
      assert_one 'codex exact positional ID then stdin' "-o $ATTEMPT/stdout.md $RESUME_SID -" "$out";;
    agy) assert_one 'agy exact conversation selector' "--conversation $RESUME_SID" "$out";;
  esac
  assert_none "$backend resume no create ID" '--session-id' "$out"
  assert_none "$backend resume no continue" '--continue' "$out"
  assert_none "$backend resume no last" '--last' "$out"
  assert_none "$backend resume no fork" '--fork-session' "$out"
  [[ "$(cat "$ATTEMPT/session.json")" == "$before" && ! -e "$ATTEMPT/events.jsonl" ]] && ok "$backend resume dry-run no observed ID mutation" || fail_msg "$backend dry-run changed metadata"
done

for id in "$SID_A" "$SID_B"; do
  make_attempt "$CRUN"
  "$PYTHON" - "$ATTEMPT" "$id" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads((p / 'session.json').read_text())
d['id'] = d['session_id'] = sys.argv[2]
(p / 'session.json').write_text(json.dumps(d))
(p / 'session-id').write_bytes((sys.argv[2] + '\n').encode())
PY
  expect_ok "same-project job $id resume" --backend claude --project "$ROOT" --run "$ATTEMPT" --resume-id "$id" --dry-run
  assert_one 'same-project job keeps own ID' "--resume $id" "$out"
done

assert_resume_block() {
  local label="$1" backend="${2:-claude}" id="${3:-$RESUME_SID}"
  shift; if (( $# )); then shift; fi; if (( $# )); then shift; fi
  rm -f "$STUBDIR/launched"
  write_event_stub "$backend"
  run_isolated --backend "$backend" --project "$ROOT" --run "$ATTEMPT" --resume-id "$id" "$@"
  if [[ "$ec" != 0 && ! -e "$STUBDIR/launched" && -f "$ATTEMPT/capture-status.txt" ]] \
    && grep -q '^VERDICT.*BLOCKED' "$ATTEMPT/last.md" && grep -q 'Evidence:' "$ATTEMPT/last.md"; then
    ok "$label blocks without provider launch"
  else fail_msg "$label (exit=$ec err=$err)"; fi
}
make_run; ATTEMPT="$LAST_TMP"; RESUME_SID="$SID_A"
assert_resume_block 'missing identity files'
for missing in session-id session.json; do
  make_attempt "$CRUN"; rm "$ATTEMPT/$missing"
  assert_resume_block "missing $missing"
done
for junk in $'\nTitle: task\n' $'\n' ' title'; do
  make_attempt "$CRUN"; printf '%s' "$junk" >>"$ATTEMPT/session-id"
  assert_resume_block 'session-id extra junk'
done
make_attempt "$CRUN"
assert_resume_block 'request ID with extra line' claude "$RESUME_SID"$'\njunk'
for change in cwd backend id session_id model effort mode persistence_available native_key; do
  make_attempt "$CRUN"
  "$PYTHON" - "$ATTEMPT/session.json" "$change" <<'PY'
import json, sys
p, key = sys.argv[1:]; d = json.load(open(p))
d[key] = False if key == 'persistence_available' else 'mismatch'
with open(p, 'w') as f: json.dump(d, f)
PY
  assert_resume_block "metadata $change mismatch"
done
make_attempt "$CRUN"
assert_resume_block 'changed model pin' claude "$RESUME_SID" --model sonnet
make_attempt "$CRUN"
assert_resume_block 'changed effort pin' claude "$RESUME_SID" --effort high
make_attempt "$CRUN"
assert_resume_block 'changed role' claude "$RESUME_SID" --mode implement
make_attempt "$SKIPRUN"
assert_resume_block 'recorded Claude persistence unavailable'
make_attempt "$CRUN"
CLAUDE_CODE_SKIP_PROMPT_HISTORY= assert_resume_block 'current Claude persistence unavailable'

# Real stub resumes: file input and argv must retain pins and the exact ID.
for backend in claude codex grok agy; do
  case "$backend" in claude) origin="$CRUN";; codex) origin="$DRUN";; grok) origin="$XRUN";; agy) origin="$ARUN";; esac
  make_attempt "$origin"; write_event_stub "$backend"
  export HS_EVENT_EC=0 HS_EVENT_TEXT='VERDICT: resumed'
  case "$backend" in
    claude|grok) export HS_EVENTS='VERDICT: resumed';;
    codex) export HS_EVENTS="{\"type\":\"thread.started\",\"thread_id\":\"$RESUME_SID\"}";;
    agy) export HS_EVENTS="{\"type\":\"init\",\"conversation_id\":\"$RESUME_SID\"}
{\"type\":\"result\",\"result\":{\"response\":\"VERDICT: resumed\",\"num_turns\":2}}";;
  esac
  run_isolated --backend "$backend" --project "$ROOT" --run "$ATTEMPT" --resume-id "$RESUME_SID"
  if [[ "$ec" == 0 && "$(cat "$ATTEMPT/last.md")" == 'VERDICT: resumed' ]] && "$PYTHON" - "$ATTEMPT" "$origin" <<'PY'
import json, pathlib, sys
p, origin = map(pathlib.Path, sys.argv[1:]); d = json.loads((p / 'session.json').read_text())
assert pathlib.Path(d['origin_run']).resolve() == origin.resolve()
assert pathlib.Path(d['attempt_run']).resolve() == p.resolve()
assert d['id'] == (p / 'session-id').read_text().strip()
assert not (p / 'report.md').exists()
PY
  then ok "$backend resumes exact identity and preserves origin"; else fail_msg "$backend resume (exit=$ec err=$err)"; fi
  if [[ "$backend" == claude || "$backend" == codex ]]; then
    brief_eq "$STUBDIR/event.stdin" "$ATTEMPT/brief.md" "$backend resume consumes continuation stdin"
  elif [[ "$backend" == grok ]]; then
    grep -Fxq "$ATTEMPT/brief.md" "$STUBDIR/event.argv" && ok 'grok resume prompt file' || fail_msg 'grok resume prompt file'
  else
    grep -Fxq "$(cat "$ATTEMPT/brief.md")" "$STUBDIR/event.argv" && ok 'agy resume continuation argv' || fail_msg 'agy resume continuation argv'
  fi
done

for backend in codex agy; do
  for observed in "$SID_B" '' missing; do
    if [[ "$backend" == codex ]]; then origin="$DRUN"; key=thread_id; kind=thread.started;
    else origin="$ARUN"; key=conversation_id; kind=init; fi
    # Choose a definitely different ID for both original sessions.
    [[ "$observed" == "$SID_B" && "$backend" == agy ]] && observed="$SID_A"
    make_attempt "$origin"; write_event_stub "$backend"
    export HS_EVENT_EC=0 HS_EVENT_TEXT='VERDICT: misleading success'
    export HS_EVENTS="{\"type\":\"$kind\",\"$key\":\"$observed\"}"
    [[ "$observed" == missing ]] && export HS_EVENTS='{"type":"result","result":{"response":"VERDICT: misleading success"}}'
    run_isolated --backend "$backend" --project "$ROOT" --run "$ATTEMPT" --resume-id "$RESUME_SID"
    if [[ "$ec" != 0 ]] && grep -q '^VERDICT.*BLOCKED' "$ATTEMPT/last.md" \
      && [[ "$(cat "$ATTEMPT/session-id")" == "$RESUME_SID" ]]; then
      ok "$backend rejects missing/different observed ID ($observed)"
    else fail_msg "$backend observed equality gate ($observed exit=$ec)"; fi
  done
done
# Production change this catches: accepting a thread.started/init that arrives
# after a parse error as proof of exact resume (CLI 0 + matching post-error ID).
for backend in codex agy; do
  if [[ "$backend" == codex ]]; then origin="$DRUN"; kind=thread.started; key=thread_id
  else origin="$ARUN"; kind=init; key=conversation_id; fi
  make_attempt "$origin"; unset HS_EVENTS_FILE; write_event_stub "$backend"
  export HS_EVENT_EC=0 HS_EVENT_TEXT='VERDICT: misleading success'
  if [[ "$backend" == codex ]]; then
    export HS_EVENTS=$'not JSON\n{"type":"'"$kind"'","'"$key"'":"'"$RESUME_SID"'"}'
  else
    export HS_EVENTS=$'not JSON\n{"type":"'"$kind"'","'"$key"'":"'"$RESUME_SID"'"}
{"type":"result","result":{"response":"VERDICT: misleading success","num_turns":2}}'
  fi
  run_isolated --backend "$backend" --project "$ROOT" --run "$ATTEMPT" --resume-id "$RESUME_SID"
  if [[ "$ec" != 0 ]] && grep -q '^VERDICT.*BLOCKED' "$ATTEMPT/last.md" \
    && [[ "$(cat "$ATTEMPT/session-id")" == "$RESUME_SID" ]] \
    && ! grep -qx ok "$ATTEMPT/capture-status.txt" \
    && ! grep -qx ok-report "$ATTEMPT/capture-status.txt"; then
    ok "$backend post-error identity is not resume proof"
  else
    fail_msg "$backend post-error identity resume fail-open (exit=$ec status=$(cat "$ATTEMPT/capture-status.txt" 2>/dev/null || true) last=$(head -n 1 "$ATTEMPT/last.md" 2>/dev/null || true))"
  fi
done
# Production change this catches: Codex resume ID match skipped when
# event_count is 0, so empty/whitespace events.jsonl + CLI 0 + -o success
# fail-opens as ok without thread.started. The "missing" fixture above
# emits a result event and cannot catch this.
for stream in empty whitespace; do
  make_attempt "$DRUN"; write_event_stub codex
  export HS_EVENT_EC=0 HS_EVENT_TEXT='VERDICT: misleading success'
  if [[ "$stream" == empty ]]; then export HS_EVENTS=''; else export HS_EVENTS=$'  \n\n\t\n'; fi
  run_isolated --backend codex --project "$ROOT" --run "$ATTEMPT" --resume-id "$RESUME_SID"
  if [[ "$ec" != 0 ]] && grep -q '^VERDICT.*BLOCKED' "$ATTEMPT/last.md" \
    && [[ "$(cat "$ATTEMPT/session-id")" == "$RESUME_SID" ]] \
    && ! grep -qx ok "$ATTEMPT/capture-status.txt" \
    && ! grep -qx ok-report "$ATTEMPT/capture-status.txt"; then
    ok "codex rejects $stream event stream resume without thread.started"
  else fail_msg "codex $stream-stream resume fail-open (exit=$ec status=$(cat "$ATTEMPT/capture-status.txt" 2>/dev/null || true) last=$(head -n 1 "$ATTEMPT/last.md" 2>/dev/null || true))"; fi
done
make_attempt "$DRUN"; write_event_stub codex
export HS_EVENT_EC=1 HS_EVENTS='' HS_EVENT_TEXT="You've hit your session limit · resets 11:30am (Europe/Vienna)"
run_isolated --backend codex --project "$ROOT" --run "$ATTEMPT" --resume-id "$RESUME_SID"
if [[ "$ec" == 1 ]] && grep -qx usage-limit "$ATTEMPT/capture-status.txt" \
  && [[ "$(head -n 1 "$ATTEMPT/last.md")" == 'VERDICT — BLOCKED: usage/rate limit' ]]; then
  ok 'codex empty-stream resume does not hide usage-limit'
else fail_msg "codex empty-stream resume hid usage-limit (exit=$ec status=$(cat "$ATTEMPT/capture-status.txt" 2>/dev/null || true))"; fi
make_attempt "$ARUN"; write_event_stub agy
export HS_EVENTS="{\"type\":\"init\",\"conversation_id\":\"$RESUME_SID\"}
{\"type\":\"result\",\"result\":{\"response\":\"VERDICT: done\",\"num_turns\":1}}"
run_isolated --backend agy --project "$ROOT" --run "$ATTEMPT" --resume-id "$RESUME_SID"
[[ "$ec" != 0 ]] && grep -q '^VERDICT.*BLOCKED' "$ATTEMPT/last.md" && ok 'agy single-turn resume rejected' || fail_msg 'agy num_turns gate'
# Production change this catches: single-turn raise happening before stdout.md
# is written, so decoded limit text never becomes classifyable evidence.
make_attempt "$ARUN"; write_event_stub agy
export HS_EVENT_EC=0 HS_EVENT_TEXT=''
export HS_EVENTS="{\"type\":\"init\",\"conversation_id\":\"$RESUME_SID\"}
{\"type\":\"result\",\"result\":{\"response\":\"$limit_text\",\"num_turns\":1}}"
run_isolated --backend agy --project "$ROOT" --run "$ATTEMPT" --resume-id "$RESUME_SID"
if [[ "$ec" != 0 ]] && grep -q '^VERDICT.*BLOCKED' "$ATTEMPT/last.md" \
  && [[ -s "$ATTEMPT/stdout.md" ]] && grep -Fq "$limit_text" "$ATTEMPT/stdout.md" \
  && grep -Fq "$limit_text" "$ATTEMPT/last.md"; then
  ok 'agy single-turn resume stays BLOCKED and retains decoded limit text'
else fail_msg "agy single-turn lost decoded limit (exit=$ec status=$(cat "$ATTEMPT/capture-status.txt" 2>/dev/null || true) stdout=$(head -c 120 "$ATTEMPT/stdout.md" 2>/dev/null || true))"; fi

# Provider tool payloads must not become the human assistant report either.
event_case agy '{"type":"tool_result","result":{"response":"VERDICT: tool output","error":"HTTP 429"}}' 0
if [[ "$ec" == 0 && ! -s "$EVENTRUN/last.md" && "$(cat "$EVENTRUN/capture-status.txt")" == no-verdict ]]; then
  ok 'agy nested tool result is neither assistant report nor limit evidence'
else fail_msg 'agy nested tool result selected as report'; fi
for backend in codex agy; do
  if [[ "$backend" == codex ]]; then init="{\"type\":\"thread.started\",\"thread_id\":\"$SID_A\"}";
  else init="{\"type\":\"init\",\"conversation_id\":\"$SID_A\"}"; fi
  event_case "$backend" "$init"$'\ninvalid JSON\n' 7
  if [[ "$ec" == 7 && "$(cat "$EVENTRUN/session-id")" == "$SID_A" ]] \
    && grep -q '^VERDICT.*BLOCKED' "$EVENTRUN/last.md" \
    && cmp -s "$EVENTRUN/events.jsonl" <(printf '%s' "$HS_EVENTS"); then
    ok "$backend later parser failure preserves early ID, raw events, and CLI exit 7"
  else fail_msg "$backend early ID and parser failure status"; fi
done
make_attempt "$CRUN"
assert_resume_block 'different resolved project' claude "$RESUME_SID" --project "$ROOT/tests"

# Production change this catches: session_data events running only after the
# CLI returns, so session-id cannot appear until the provider is allowed to exit.
for backend in codex agy; do
  rm -f "$STUBDIR/stream-release"
  if [[ "$backend" == codex ]]; then
    stream_event="{\"type\":\"thread.started\",\"thread_id\":\"$SID_A\"}"
  else
    stream_event="{\"type\":\"init\",\"conversation_id\":\"$SID_A\"}"
  fi
  cat >"$STUBDIR/$backend" <<EOF
#!/bin/bash
set -euo pipefail
: "\${HS_STUB_DIR:?}"
printf '%s\n' "\$@" >"\$HS_STUB_DIR/event.argv"
cat >/dev/null
target=""
while [[ \$# -gt 0 ]]; do
  if [[ "\$1" == -o ]]; then target="\$2"; shift 2; else shift; fi
done
if [[ -n "\$target" ]]; then printf 'VERDICT: streamed\n' >"\$target"; fi
printf '%s\n' '$stream_event'
while [[ ! -f "\$HS_STUB_DIR/stream-release" ]]; do sleep 0.05; done
exit 0
EOF
  chmod +x "$STUBDIR/$backend"
  make_run; STREAMRUN="$LAST_TMP"
  stream_out="$(mktemp "${TMPDIR:-/tmp}/hs-out.XXXXXX")"
  stream_err="$(mktemp "${TMPDIR:-/tmp}/hs-err.XXXXXX")"
  WORK+=("$stream_out" "$stream_err")
  PATH="$STUBDIR:$ORIG_PATH" "$BASH_BIN" "$SPAWN" --backend "$backend" --project "$ROOT" --run "$STREAMRUN" >"$stream_out" 2>"$stream_err" &
  spawn_pid=$!
  deadline=$((SECONDS + 8))
  saw_live=0
  while [[ ! -f "$STREAMRUN/session-id" ]]; do
    if [[ "$SECONDS" -ge "$deadline" ]] || ! kill -0 "$spawn_pid" 2>/dev/null; then
      break
    fi
    sleep 0.05
  done
  if [[ -f "$STREAMRUN/session-id" && ! -f "$STUBDIR/stream-release" ]] && kill -0 "$spawn_pid" 2>/dev/null; then
    saw_live=1
  fi
  touch "$STUBDIR/stream-release"
  set +e
  wait "$spawn_pid"
  stream_ec=$?
  set -e
  if [[ "$saw_live" -eq 1 && "$(cat "$STREAMRUN/session-id" 2>/dev/null || true)" == "$SID_A" && -s "$STREAMRUN/session.json" ]]; then
    ok "$backend persists ID while CLI still running"
  else
    fail_msg "$backend live persist (saw=$saw_live id=$(cat "$STREAMRUN/session-id" 2>/dev/null || true) exit=$stream_ec err=$(tr '\n' '|' <"$stream_err"))"
  fi
  if [[ "$stream_ec" -eq 0 ]]; then
    ok "$backend live persist preserves CLI 0"
  else
    fail_msg "$backend live persist CLI status (exit=$stream_ec)"
  fi
  if grep -Fq "$SID_A" "$STREAMRUN/events.jsonl" 2>/dev/null; then
    ok "$backend live persist keeps identity event in events.jsonl"
  else
    fail_msg "$backend live persist events.jsonl missing identity"
  fi
done

# Stub both interpreter names; missing JSON consumer must fail before a model job.
for candidate in python python3; do
  printf '#!/bin/bash\nexit 1\n' >"$STUBDIR/$candidate"
  chmod +x "$STUBDIR/$candidate"
done
make_run; DEPENDENCY_RUN="$LAST_TMP"
rm -f "$STUBDIR/launched"
write_event_stub codex
run_isolated --backend codex --project "$ROOT" --run "$DEPENDENCY_RUN"
if [[ "$ec" != 0 && ! -e "$STUBDIR/launched" ]] && grep -q '^VERDICT.*BLOCKED' "$DEPENDENCY_RUN/last.md"; then
  ok 'missing JSON consumer blocks before launch'
else fail_msg 'missing JSON consumer did not block'; fi
rm "$STUBDIR/python" "$STUBDIR/python3"

# uuidgen is optional; when available its uppercase output is canonicalized.
cat >"$STUBDIR/uuidgen" <<'EOF'
#!/bin/bash
printf 'ABCDEFAB-1234-4567-89AB-ABCDEFABCDEF\n'
EOF
chmod +x "$STUBDIR/uuidgen"
write_event_stub grok
export HS_EVENTS='VERDICT: UUID stub' HS_EVENT_EC=0
make_run; UUIDRUN="$LAST_TMP"
run_isolated --backend grok --project "$ROOT" --run "$UUIDRUN"
if [[ "$ec" == 0 && "$(cat "$UUIDRUN/session-id")" == abcdefab-1234-4567-89ab-abcdefabcdef ]]; then
  ok 'uuidgen canonical lowercase identity'
else fail_msg 'uuidgen identity normalization'; fi
printf '#!/bin/bash\nprintf invalid\n' >"$STUBDIR/uuidgen"
make_run; UUIDRUN="$LAST_TMP"; rm -f "$STUBDIR/launched"
run_isolated --backend grok --project "$ROOT" --run "$UUIDRUN"
[[ "$ec" != 0 && ! -e "$STUBDIR/launched" && "$err" == *'UUID source returned invalid'* ]] && ok 'invalid UUID source fails before launch' || fail_msg 'invalid UUID source accepted'
rm "$STUBDIR/uuidgen"

echo
echo "passed=$pass failed=$fail"
[[ "$fail" -eq 0 ]]
