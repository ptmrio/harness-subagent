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
assert_one "agy review output text" "--output-format text" "$out"
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

expect_ok "dry-run codex --effort in -c" \
  --backend codex --project "$ROOT" --run "$RUN" --model gpt-5.6-sol --effort xhigh --dry-run
assert_one "codex model" "-m gpt-5.6-sol" "$out"
assert_one "codex effort -c" "-c model_reasoning_effort=xhigh" "$out"
assert_one "codex default-mode review approve-for-me" "--approve-for-me" "$out"
assert_none "codex default-mode review no sandbox" "--sandbox" "$out"

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
echo CODEX_STDOUT
EOF

write_stub_common agy
printf '%s\n' 'echo AGY_MARKER' >>"$STUBDIR/agy"

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
EOF
chmod +x "$STUBDIR/claude"
make_run
URUN="$LAST_TMP"
run_isolated --backend claude --mode review --project "$ROOT" --run "$URUN"
if [[ "$(head -n 1 "$URUN/last.md")" == "VERDICT — BLOCKED: usage/rate limit" && "$(cat "$URUN/capture-status.txt")" == "usage-limit" ]]; then
  ok "claude usage-limit becomes BLOCKED VERDICT"
else
  fail_msg "claude usage-limit (last=$(head -c 200 "$URUN/last.md" 2>/dev/null || true) status=$(cat "$URUN/capture-status.txt" 2>/dev/null || true))"
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

echo
echo "passed=$pass failed=$fail"
[[ "$fail" -eq 0 ]]
