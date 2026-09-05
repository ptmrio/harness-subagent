# Usage-limit capture (S0) Implementation Plan

> **For agentic workers:** Implement this plan task-by-task using `superpowers:executing-plans` when execution is separately authorized. Steps use checkbox (`- [x]`) syntax for tracking. This planning job does not execute the plan, spawn workers, or commit.

**Goal:** Finalize every returned CLI invocation, preserve its exit status, and produce useful blocked captures for usage/rate-limit diagnostics on either captured stream.

**Architecture:** Patch the existing dispatch and capture functions in `scripts/spawn.sh`. Preserve report selection and normalization, then classify diagnostics from both captured streams and the selected-text fallback before concluding that output is empty. Keep recovery decisions in the parent protocol.

**Tech Stack:** Bash with `set -euo pipefail`, existing grep/sed/awk utilities, and the PATH-isolated Bash regression suite; Git Bash on Windows.

**Spec:** [Locked design, 2026-09-05](../specs/2026-09-05-limit-resume-design.md), specifically S0 and its shipping gates. The spec is normative.

## Global Constraints

- “Existing capture artifacts only. No persistence, resume, scheduler, or new status schema.”
- “Keep validation, command construction, `cd`, and dry-run handling outside this guard.”
- “Each dispatch branch must leave the CLI invocation as its final command so later bookkeeping cannot overwrite its status.”
- “Keep `set -e` elsewhere; do not globally disable it or hide finalization failures with `|| true`.”
- “Successful finalization preserves the original CLI status exactly: a captured failure still exits nonzero.”
- “Capture I/O failures remain visible failures; they must never become success.”
- “Never rewrite the durable report or raw logs.”
- “Explicit credits/spend evidence takes precedence over a generic 429 label.”
- “The parent owns waiting and any retry decision.”
- “With S0 alone, these artifacts enable recovery decisions but do not provide conversation resume.”
- Retain Claude `-p`, file stdin, `--no-session-persistence`, Codex `--ephemeral`, all route/model/effort pins, and role/tool restrictions. Do not reopen provider research or TUI decisions.
- No commits are required; commit only if a later human explicitly asks.

## Files and verification approach

| Existing file | Responsibility in this plan |
|---|---|
| `scripts/spawn.sh` | Guard only the final CLI dispatch; finalize output; classify limits without changing raw artifacts. |
| `tests/spawn_test.sh` | Truthful exit-1 regression and isolated fixtures for status, streams, diagnostics, and precedence. |
| `SKILL.md` | S0 parent wording: completion versus success, sticky routing, evidence-based recovery. Read/edit only the relevant parent-protocol passages. |
| `references/backend-claude.md` | Keep Claude capture/recovery wording consistent with that parent contract. |

No production or test files need to be created. The existing approximately 288-line script is small enough to patch in place. Symbol names and observable behavior below identify edit sites; line numbers are not contracts.

Run all implementation gates from the repository root in Git Bash: `bash tests/spawn_test.sh`. The suite has no subset selector, so this plan uses the full suite at every task gate. Use the existing `run_isolated` helper, which records `ec` without aborting the test runner. Use an ordinary parent test shell without an inherited worker marker; retain the suite's explicit nested-spawn rejection tests. Never invoke real provider CLIs. This planning delivery does not run this suite or claim implementation gates passed.

### Task 1: Finalize nonzero CLI returns without losing their status

**Files:** Modify `scripts/spawn.sh` at the final dispatch and finalization call; modify `tests/spawn_test.sh` at the existing Claude usage-limit stub and capture fixtures.

**Interfaces:** Consume the existing `run_isolated` result variable `ec` and run-directory artifacts. Produce the contract that every returned backend invocation reaches the existing `finalize_capture`; successful finalization returns the original CLI exit code. No dispatch arguments or redirections change.

- [x] **Write the failing regression:** Append literal `exit 1` after the current session-limit stub's `printf`. Update its existing assertion to require all three outcomes together:

  ```bash
  if [[ "$ec" -eq 1 && -f "$URUN/last.md" && -f "$URUN/capture-status.txt" ]] \
    && [[ "$(head -n 1 "$URUN/last.md")" == 'VERDICT — BLOCKED: usage/rate limit' ]] \
    && grep -qx 'usage-limit' "$URUN/capture-status.txt"; then
    ok 'claude exit-1 usage-limit preserves status and blocked capture'
  else
    fail_msg "claude exit-1 usage-limit capture (exit=$ec)"
  fi
  ```

- [x] **Add focused capture fixtures:** Put this test-only helper and its calls after the existing backend live checks, before the final totals, so replacing stubs cannot contaminate earlier argv/stdin tests. It reuses `make_run`, `run_isolated`, `ok`, and `fail_msg`; the `CAPRUN` result exposes artifacts to subsequent assertions. Its optional final arguments are report text, preexisting last text, backend, and whether Codex omits its `-o` file. These are test inputs, not new production interfaces.

  ```bash
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
  ```

  When inserting the fenced helper into the shell file, place the heredoc delimiter `EOF` at column zero. Assertions check artifacts and codes, not internal helper names or source layout.

- [x] **Run the red gate:** `bash tests/spawn_test.sh`. Expect the truthful limit stub and generic/empty/report nonzero fixtures to fail because `last.md` or status is missing. Existing successful captures should still pass. A missing tool or syntax error is not the intended red result.

- [x] **Implement the guarded dispatch:** Initialize `cli_ec=0` immediately before the existing final `case "$BACKEND" in`; replace that case's closing `esac` with `esac || cli_ec=$?`; retain the standalone `finalize_capture` and append `exit "$cli_ec"`. The resulting control flow is exactly the locked shape:

  ```bash
  cli_ec=0
  case "$BACKEND" in
    claude) "${CMD[@]}" < "$BRIEF" > "$STDOUT" 2> "$ERR" ;;
    codex)  "${CMD[@]}" < "$BRIEF" 2> "$ERR" ;;
    grok)   "${CMD[@]}" < /dev/null > "$STDOUT" 2> "$ERR" ;;
    agy)    "${CMD[@]}" -p "$(cat "$BRIEF")" < /dev/null > "$STDOUT" 2> "$ERR" ;;
  esac || cli_ec=$?
  finalize_capture
  exit "$cli_ec"
  ```

  Do not wrap `finalize_capture` in a conditional or an OR-list: Bash would suppress its normal `errexit` behavior. Do not add bookkeeping after a branch's CLI invocation. No persistence changes belong in this task.

- [x] **Run the green gate:** `bash tests/spawn_test.sh`. Require suite exit 0 and `failed=0`, including exact exit 1/7 preservation and existing parser, dry-run, argv/stdin, report preference, and normalization checks. Review the diff to confirm the guard encloses only dispatch. Finalization I/O errors remain visible nonzero failures; preserving the CLI code is guaranteed after successful finalization, not forced process termination or storage failure.

### Task 2: Detect existing limit diagnostics across both streams before empty-output handling

**Files:** Modify `scripts/spawn.sh` in `detect_usage_limit` and `finalize_capture`; extend the capture fixtures in `tests/spawn_test.sh`.

**Interfaces:** Consume Task 1's exit-preserving finalization and `capture_case(label, stdout, stderr, exit, status, first, report?, fallback?, backend?, omit_output?)`. Keep `detect_usage_limit "$LAST"` as a standalone call; it examines `$STDOUT`, `$ERR`, and selected `$LAST`, writes only `$LAST` and `$STATUS`, and returns 0 on ordinary match/no-match. I/O failures remain failures. A selected valid verdict bypasses diagnostic classification.

- [x] **Write the failing stream regressions:** Append these calls after the helper. The first fixture is mandatory: empty stdout, stderr-only diagnostic, explicit exit 1.

  ```bash
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
  ```

- [x] **Run the red gate:** `bash tests/spawn_test.sh`. Expect stderr-only/missing-output detection and source-label assertions to fail. Report and stdout verdict precedence should already pass; retain those as regression guards.

- [x] **Implement stream scanning and evidence preservation:** Retain the existing pattern for this task. Replace the detector's single-file scan with the following body. Build evidence before writing the selected file so a `last.md` fallback cannot be truncated before reading. Preserve full matching-source contents to retain reset/retry hints on adjacent lines. Skip a duplicate fallback scan when nonempty stdout was selected. Filenames identify streams; no new artifact or reason schema is introduced.

  ```bash
  detect_usage_limit() {
    local f="$1" source raw evidence='' grep_ec
    local pattern='session limit|rate[[:space:]-]?limit|usage[[:space:]-]?limit|hit your (session )?limit|you.ve hit your'
    has_verdict "$f" && return 0
    for source in "$STDOUT" "$ERR" "$f"; do
      [[ -s "$source" ]] || continue
      if [[ "$source" == "$f" && -s "$STDOUT" ]]; then continue; fi
      if grep -qiE "$pattern" "$source"; then
        raw="$(cat "$source")"
        evidence+=$'\n--- '"${source##*/}"$' ---\n'"$raw"$'\n'
      else
        grep_ec=$?
        if [[ "$grep_ec" -gt 1 ]]; then return "$grep_ec"; fi
      fi
    done
    [[ -n "$evidence" ]] || return 0
    printf '%s\n' \
      'VERDICT — BLOCKED: usage/rate limit' \
      '' \
      'UNVERIFIED — Limit diagnostic captured. Keep the selected backend/model (sticky route). The parent owns waiting and any retry decision; inspect the preserved evidence for reset/retry guidance or ask the human when unclear.' \
      "$evidence" >"$f"
    printf 'usage-limit\n' >"$STATUS"
  }
  ```

- [x] **Implement finalization ordering:** Keep report-with-verdict → stdout → existing-last selection, then normalize, then detect, then decide the capture token. In the current empty branch create an empty `last.md` but remove the early `return 0`. The complete sequence can remain within the existing function:

  ```bash
  finalize_capture() {
    if [[ -s "$REPORT" ]] && has_verdict "$REPORT"; then
      cp "$REPORT" "$LAST"
      printf 'ok-report\n' >"$STATUS"
    elif [[ -s "$STDOUT" ]]; then
      cp "$STDOUT" "$LAST"
      printf 'ok\n' >"$STATUS"
    elif [[ -s "$LAST" ]]; then
      printf 'ok\n' >"$STATUS"
    else
      : >"$LAST"
      printf 'no-verdict\n' >"$STATUS"
    fi
    normalize_verdict "$LAST"
    detect_usage_limit "$LAST"
    if grep -qx 'usage-limit' "$STATUS"; then return 0; fi
    if has_verdict "$LAST"; then
      if [[ -s "$REPORT" ]] && has_verdict "$REPORT"; then
        printf 'ok-report\n' >"$STATUS"
      else
        printf 'ok\n' >"$STATUS"
      fi
    else
      printf 'no-verdict\n' >"$STATUS"
    fi
  }
  ```

- [x] **Run the green gate:** `bash tests/spawn_test.sh`. Require exit 0 and `failed=0`; verify empty and missing stdout, raw-stream/report byte preservation, selected-last fallback, source labels, reset/timezone evidence, valid-verdict precedence, and CLI exit preservation. A valid report with exit 7 must remain `ok-report` plus exit 7, never an automatic job pass.

### Task 3: Expand diagnostic forms and align the S0 parent recovery contract

**Files:** Modify `scripts/spawn.sh` in the detector's pattern and synthesized parent guidance; extend `tests/spawn_test.sh`; update only the S0 parent passages in `SKILL.md` (Sticky route, Shared protocol step 3, Hang/progress hygiene, related red flags) and `references/backend-claude.md` (Capture hardening).

**Interfaces:** Consume Task 2's source-preserving detector and fixture helper. Produce one unchanged `usage-limit` token plus the exact blocked first line, original evidence, source labels, and parent-owned action guidance. Limit subtype remains a parent interpretation, not a new parser/API.

- [x] **Write the failing diagnostic matrix:** Run each positive form in both stdout and stderr positions; mixed case verifies case-insensitivity. Add benign prose and bare-exit controls. Assert the diagnostic survives synthesis, not only the classification.

  ```bash
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
  ```

- [x] **Run the red gate:** `bash tests/spawn_test.sh`. Expect the newly introduced HTTP/quota/credits/spend positives to fail under the Task 2 phrase set. The original session/rate/usage patterns, benign prose, and precedence guards must continue passing.

- [x] **Implement diagnostic matching:** Extend the existing `pattern` variable with diagnostic-shaped alternatives, using `grep -qiE` as before. Require HTTP/status/error context for numeric 429 rather than matching any occurrence of the number. Require an exhaustion/exceeded/insufficient state for quota/credits and reached/exceeded/exhausted state for spend caps. A concrete initial expression supporting the matrix is:

  ```bash
  local pattern='session limit|rate[[:space:]-]?limit|usage[[:space:]-]?limit|hit your (session )?limit|you.ve hit your'
  pattern+='|(^|[^[:alnum:]_])(http(/[0-9.]+)?|http status|status([[:space:]_-]+code)?|error)[[:space:]:=]+429([^[:digit:]]|$)|too many requests'
  pattern+='|(quota[[:space:]_:=-]+((has been|is)[[:space:]]+)?(exhausted|exceeded))|((exhausted|exceeded)[[:space:]_:=-]+(paid[[:space:]]+)?quota)'
  pattern+='|((insufficient|exhausted)[[:space:]_:=-]+credits)|(credits[[:space:]_:=-]+((are|have been)[[:space:]]+)?(insufficient|exhausted))'
  pattern+='|((spend(ing)?[[:space:]_-]+(limit|cap))[[:space:]:=-]+((has been|is)[[:space:]]+)?(reached|exceeded|exhausted))'
  ```

  Pin observed diagnostic behavior through fixtures, not the precise regex text. Do not infer a backend-specific Grok/agy subtype from these generic strings. Preserve all relevant sources when a generic 429 and explicit spend evidence coexist.

- [x] **Implement parent guidance with concrete copy:** Replace the detector's interim guidance string with the following prose (it may be emitted as several `printf` arguments). Keep the first line and status token unchanged, and append the captured evidence unchanged.

  > UNVERIFIED — Child returned limit evidence, not a completed report. Keep the selected backend/model and route pins (sticky route). The parent owns waiting and any retry decision. For a subscription/session window, wait for the stated reset and preserve its timezone. For a transient HTTP 429 / Too Many Requests without stronger spend/quota evidence, use a short backoff and honor any retry hint. Explicit insufficient credits, spend cap, or exhausted paid quota takes precedence over generic 429: ask the human; do not enable spend or change billing automatically. For ambiguous quota evidence without a reliable cause/reset, report it and ask once. Do not invent a reset or retry indefinitely. Spawn does not sleep, launch a sleeper, or change routes. S0 does not provide conversation resume.

  This is guidance for interpreting evidence, not a claim that all classes occurred in this attempt. Only the preserved diagnostic supplies actual reset/timezone/retry values.

- [x] **Update the two parent-protocol documents:** Incorporate these exact behavioral statements in the existing sections, replacing inconsistent blanket “ask once / wait” wording where it conflicts. Keep unrelated nesting-leak handling and headless invocation guidance intact.

  > Done means the process exited and capture artifacts exist. Success additionally requires the CLI exit status and report verdict to support success. Read `last.md`, `capture-status.txt`, and the process exit status together; `ok` and `ok-report` describe capture, not successful job completion. A valid report with a nonzero CLI exit requires parent review and is not an automatic pass. Generic non-limit errors remain `no-verdict` failures.
  >
  > For `usage-limit`, inspect the preserved stdout/stderr evidence. Subscription/session exhaustion: wait for the stated reset, retaining timezone. Transient 429 / Too Many Requests without stronger spend/quota evidence: short backoff, honoring a retry hint. Insufficient credits, spend cap, or exhausted paid quota: ask the human before enabling spend; explicit spend evidence overrides a generic 429. Ambiguous quota with no reliable cause/reset: report the evidence and ask once. Do not invent reset values, purchase credits, or retry indefinitely. The parent owns waiting and retry decisions; keep the backend/model and route pins sticky, stop dependent stages, and do not ask spawn to sleep or launch a sleeper. S0 capture supports recovery decisions but does not provide conversation resume.

  In the Claude Capture hardening list, state that returned nonzero exits now finalize, raw stderr is inspected alongside captured stdout when the selected text has no verdict, and selected valid verdicts retain precedence. Retain report-before-cleanup, `-p`, file input, and the existing no-persistence flag. Do not add S1/S2 execution instructions.

- [x] **Run the green gate:** `bash tests/spawn_test.sh`. Require exit 0 and `failed=0` across both stream positions, negative controls, combined evidence, and all earlier regressions. Manually review the emitted generic-429, session-reset, combined-credits, and ambiguous-quota captures against the parent-action table in the locked spec: no invented timing, credits evidence overrides a generic 429, and the parent owns action. Review both documentation diffs for the same rules and done/success distinction; avoid brittle tests that grep documentation for exact prose.

## Out of this plan: S1 + S2

Persistence, session-ID capture, backend/cwd binding, durable parent wait records, short `resume.md`, and exact-ID continuation belong to the locked spec's [S1+S2 follow-on contracts and gates](../specs/2026-09-05-limit-resume-design.md#s1s2-follow-on-persistence-and-exact-id-resume-contracts). They require a separate follow-on plan and provider verification; none is a prerequisite or implementation task here.

## Plan self-check and handoff

- [x] Task 1 covers truthful exit-1 behavior, ordinary/empty failure capture, non-1 status preservation, all backend dispatch branches, and valid-report/nonzero coexistence.
- [x] Task 2 covers the mandatory stderr-only fixture, missing Codex output, raw-artifact preservation, selected-last fallback, source/reset evidence, and verdict precedence/normalization.
- [x] Task 3 covers both-stream HTTP/quota/credits/spend diagnostics, benign controls, combined-evidence precedence, parent actions, and done versus success wording.
- [x] Every task has an explicit red → implementation → green sequence using `bash tests/spawn_test.sh`; no commit gate, new production files, persistence work, or provider research is required.

No unknown blocks S0 planning. Exact Grok/agy quota strings and subtype mappings remain unverified as recorded by the spec; generic S0 fixtures do not claim provider-specific coverage. Provider identity extraction and exact-resume behavior remain follow-on verification. Execute only under a later implementation instruction; this document alone records a plan, not passing implementation tests.

## Authorized S1 + S2 implementation train

The implementation brief extends this train after S0; the S0 plan above remains historical and unchanged except completion checkboxes.

- [x] S1 red gate: persistent fresh argv, preassigned and early observed IDs, JSON extraction/error handling.
- [x] S1 implementation and green gate; document Python consumer and identity availability.
- [x] S2 red gate: exact resume argv, route/cwd/ID validation, no-launch blocks, observed equality gates.
- [x] S2 implementation and green gate; document parent wait/checkpoint/attempt protocol.
- [x] Final full stub suite, diff review, and external report; no commit or provider jobs.
