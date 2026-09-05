# Usage-limit capture + exact-ID resume

**Status:** locked by the human 2026-09-05; this authorized train ships S0, then S1 persistence, then S2 exact-ID resume; all product locks retained  
**Date:** 2026-09-05  
**Repo:** `ptmrio/harness-subagent`  
**Trigger:** live Claude `-p` subscription limit returned a stdout one-liner and exit 1, but spawn produced neither `last.md` nor `capture-status.txt`. The existing stub exits 0 and gives a false green.

## Practices (dated)

Use the research supplied by the human on 2026-09-05 and the checked-in backend references; no new provider research is needed for this design.

1. **Anthropic — headless capture and persistence.** [Claude reference](../../../references/backend-claude.md): retain `-p`, file stdin, and the durable `report.md` checkpoint. The current `--no-session-persistence` prevents conversation resume. The supplied research supports a later preassigned UUID and exact `--resume <id>` with a short continuation prompt.
2. **OpenAI — one-shot capture and persistence.** [Codex reference](../../../references/backend-codex.md): `--ephemeral` means no session files. It is the same persistence obstacle as Claude's no-persist flag; an ID alone cannot restore an ephemeral conversation.

**Peer patterns, supplied research 2026-09-05:** adopt the exact provider cursor plus cwd identity from T3 Code, OpenHands, and claude-hibernate. Adopt a parent-owned wait record inspired by carry-on. OneHarness and Cursor Cloud were also considered in that research; no extra subsystem is needed here. Reject silent fresh-thread fallback, a two-second force-kill, cross-backend failover, and a detached sleeper inside spawn.

**Conflict:** one-shot process completion and captured text do not establish job success. Preserve the CLI exit code, inspect the verdict, and keep the selected route sticky.

## Problem

`scripts/spawn.sh` uses `set -euo pipefail`. Its final CLI `case` is unguarded, so a nonzero CLI return exits before `finalize_capture`. The usage-limit stub in `tests/spawn_test.sh` ends with a successful `printf`, never exercising the live exit-1 path.

`detect_usage_limit` currently scans only the selected `last.md`, uses Claude-shaped phrases, and skips text containing a verdict. Finalization also returns early when no report/stdout/last text exists. Consequently, merely adding stderr patterns after that return would still miss stderr-only failures.

Resume is a separate gap: Claude and Codex explicitly disable persistence; Grok and agy persist conversations, but spawn's plain/text capture discards their IDs. A shared `--project` can contain several workers' sessions. Resuming the most recent session can attach the wrong job.

## Design

### Alternatives and selected slice

| Slice | Value | Cost / boundary |
|---|---|---|
| **S0 Capture — selected now** | Finalize after nonzero return; make the exit-1 stub truthful; scan stdout and stderr for limit diagnostics. Fixes the live missing-artifact hole. | Existing capture artifacts only. No persistence, resume, scheduler, or new status schema. |
| **S1 Persist — follow-on** | Remove Claude `--no-session-persistence` and Codex `--ephemeral`; save `$RUN/session-id` and backend-specific identity as soon as known. | Requires reliable provider identity capture and persistent-session verification. Does not itself resume work. |
| **S2 Resume — follow-on, depends on S1** | Parent resumes the exact session after reset/backoff, using short `resume.md`. | Requires the identity and parent wait contracts below. Never re-pipes the full brief. |

**Recommendation:** ship S0 immediately. Define S1+S2 together below, but do not make either a dependency of S0. A smaller patch using `|| true` and losing the CLI status is rejected.

### S0: finalize every CLI return; preserve its exit status

Use the guarded dispatch shape selected by the Astra review on 2026-09-05:

```bash
cli_ec=0
case "$BACKEND" in
  # Existing CLI branches and redirections.
esac || cli_ec=$?
finalize_capture
exit "$cli_ec"
```

This is the normative control-flow shape, not a replacement implementation. Keep validation, command construction, `cd`, and dry-run handling outside this guard. Each dispatch branch must leave the CLI invocation as its final command so later bookkeeping cannot overwrite its status. Keep `set -e` elsewhere; do not globally disable it or hide finalization failures with `|| true`.

Every returned CLI invocation reaches finalization, including ordinary errors and exit 1. Successful finalization preserves the original CLI status exactly: a captured failure still exits nonzero. Capture I/O failures remain visible failures; they must never become success. Process termination before control returns is outside S0's guarantee.

**Done** means the process exited and capture artifacts exist. **Success** additionally requires the CLI status and report to support success. `ok` and `ok-report` describe capture, not successful completion of the job.

### S0: classify diagnostics across both streams

Keep the current artifact contract: raw captured stdout in `$RUN/stdout.md`, stderr in `$RUN/stderr.log`, durable child checkpoint in `$RUN/report.md`, normalized result in `$RUN/last.md`, and capture classification in `$RUN/capture-status.txt`.

1. Preserve verdict selection and normalization: prefer a `report.md` containing VERDICT, otherwise captured stdout, with the existing last-text fallback. Never rewrite the durable report or raw logs.
2. When the selected text has no verdict, inspect both captured stdout and stderr for limit diagnostics, even if stdout is empty or missing. Run this check before the empty-output early return. Retain detection of the existing selected-text fallback.
3. Retain current session/usage/rate-limit phrases and add diagnostic forms of `429`, `Too Many Requests`, exhausted/exceeded `quota`, and insufficient/exhausted `credits` or spend-limit errors. Match case-insensitively. A bare exit 1 is not evidence; ordinary prose mentioning quota or credits is not exhaustion evidence either.
4. On a match, synthesize `VERDICT — BLOCKED: usage/rate limit` in `last.md` and write exactly `usage-limit` to `capture-status.txt`. Include the matched diagnostic, identify its stream, and retain any stated reset time/timezone or retry hint without inventing missing values. State the sticky route and parent-owned next action.
5. Without a verdict or a limit diagnostic, produce `last.md` (empty if necessary) and `no-verdict`. Generic nonzero errors remain generic failures. Valid existing verdicts retain their current precedence; incidental stderr must not overwrite them. A valid report plus a nonzero CLI exit still requires parent review and is not an automatic pass.

S0 keeps one `usage-limit` capture token. The parent distinguishes the reason from the preserved diagnostic; no new parser framework or machine-readable reason schema is required.

| Evidence | Meaning | Parent action |
|---|---|---|
| Subscription/session window exhausted, often with a reset | Subscription window | Wait for the stated reset; if proceeding requires credits, ask the human before enabling spend. |
| API HTTP 429 / Too Many Requests without stronger quota/spend evidence | Transient rate limit | Short backoff, honoring an available retry hint; retain the same route. |
| Insufficient credits, spend cap, or exhausted paid quota | Credits/spend block | Ask the human. Do not purchase credits or change billing automatically. |
| Ambiguous quota diagnostic with no reliable reset or cause | Limit, subtype unverified | Report the evidence and ask once; do not invent a reset or retry indefinitely. |

Explicit credits/spend evidence takes precedence over a generic 429 label. The parent owns waiting and any retry decision. The child returns BLOCKED plus artifacts; `spawn.sh` does not sleep until reset, launch a sleeper, or swap backends. With S0 alone, these artifacts enable recovery decisions but do not provide conversation resume.

### S1+S2 follow-on: persistence and exact-ID resume contracts

**Identity.** The resumable identity is the selected backend, exact provider-native session/thread ID, and resolved original execution cwd (`--project`), bound to the originating run and durable report path. Model/effort pins and role restrictions remain attached to that run. An ID from a different backend or cwd is invalid for this job.

S1 writes `$RUN/session-id` containing the exact provider ID as soon as it is known, alongside the backend-specific ID record and backend/cwd binding. These records must agree; absence or disagreement means unavailable resume, not permission to guess. A preassigned ID records intent, not proof that a provider persisted a session. Do not defer ID capture until a final assistant response that a limit may prevent.

| Backend | S1 contract | S2 contract |
|---|---|---|
| Claude | Drop `--no-session-persistence`; preassign and record a UUID before launch, and supply it as the provider session identity. Retain `-p`. | Exact `--resume <id>` with a short continuation prompt supplied through the established file-input path. |
| Codex | Drop `--ephemeral`; record the exact provider thread/session ID when emitted and retain its backend-specific identity. | Use the provider's exact-ID resume operation for that persisted thread. |
| Grok | Persistence already exists; capture the provider ID currently discarded by plain output. | Resume only the recorded provider ID in its original cwd. |
| agy | Persistence already exists; capture the provider ID currently discarded by text output. | Resume only the recorded provider ID in its original cwd. |

Backend adapters must verify their ID source and exact-resume behavior before claiming support. Do not invent Grok/agy ID extraction or resume flags in this spec. Any structured-output adaptation must preserve the human-readable capture contract; raw event envelopes are not `last.md`.

**Parent wait record.** Before yielding for a reset/backoff, the parent durably records the original run/report paths, backend, exact provider ID if available, resolved cwd, route pins, blocked reason and raw evidence, known reset/retry time (including timezone), and next action. Unknown time or unavailable ID is explicit. This is a parent checkpoint inspired by carry-on, not a scheduler or a sleeper owned by spawn.

**Resume handoff.** After the reset/backoff or the human's credits decision, the parent confirms the prior process exited and the identity matches, then launches a continuation with at most one active attempt for that job. Preserve the blocked attempt's artifacts and use a separate attempt run directory tied to the original checkpoint. Resume uses the original cwd and backend, even though capture artifacts live in the new attempt directory.

The parent supplies only a short `resume.md`: continue the unfinished work, read the durable `report.md` checkpoint at its explicit path, retain the original scope and worker/no-spawn fence, and write the updated complete report to the current attempt's run directory before cleanup. Preserve role/tool restrictions. Never re-pipe the original full brief or replay already completed work as a new assignment.

Never select a shared project's most recent conversation via `--continue`, `--last`, or a continuation shorthand such as `-c`. This prohibition concerns session selection; Codex's existing `-c model_reasoning_effort=...` configuration option is unrelated and remains valid.

If the ID is missing, persistence unavailable, session absent, identity mismatched, or exact resume rejected, return BLOCKED with evidence. No silent fresh-thread fallback, cross-backend failover, or two-second force-kill. A fresh run from the durable checkpoint is a separate explicit recovery decision, never represented as a successful resume. A repeated limit returns another BLOCKED capture to the parent; spawn never enters a wait/retry loop.

**Checkpoint priority.** `report.md` remains the durable job checkpoint and must be written before cleanup. Resume adds conversation context; it does not replace the report, prove work completed, or guarantee exactly-once tool effects. The continuing worker reconciles the checkpoint with actual work before repeating actions.

## Non-goals

- Switching Claude from `-p` to a TUI, `--bg`, or `--mode visual` as a limit workaround; visual still uses `-p`.
- Persistence or resume implementation in S0; changing existing no-persist flags before the follow-on.
- Automatic billing changes, backend/model failover, a scheduler, or a detached wait service.
- Recovering from forced process death or general capture-storage failures in this slice.
- Replacing durable reports with provider history, or treating capture success as job success.
- Reopening locked product decisions or repeating the supplied research.

## Files (future implementation scope)

| Slice | File | Change |
|---|---|---|
| S0 | `scripts/spawn.sh` | Guard dispatch, preserve CLI exit, finalize nonzero returns, detect both streams before empty-output return. |
| S0 | `tests/spawn_test.sh` | Truthful exit-1 limit stub and focused capture regressions. |
| S0 | `SKILL.md`, `references/backend-claude.md` | Clarify done versus success, limit classes, and parent wait ownership while retaining sticky routing. |
| S1+S2 | `scripts/spawn.sh`, tests, `SKILL.md`, four backend references | Persistence/ID capture and parent exact-ID continuation contract, implemented in a separate follow-on. |

This design task writes only this spec and its required external run report; it does not change the implementation, commit, or write an implementation plan.

## Acceptance

### S0 shipping gates

- [ ] The existing Claude session-limit stub explicitly executes `exit 1`; its assertion requires `ec == 1`, the BLOCKED first line, and `capture-status.txt == usage-limit` together.
- [ ] A stderr-only limit with empty stdout and exit 1 produces the same BLOCKED/status artifacts and preserves the exit code. The original diagnostic remains in `stderr.log`.
- [ ] Focused fixtures cover 429 / Too Many Requests, exhausted quota, and credits/spend diagnostics in both stream positions; benign mentions alone are not classified as limits.
- [ ] A generic non-limit error preserves its nonzero code and produces `no-verdict`; empty output still finalizes. A non-1 failure code also survives finalization.
- [ ] Existing report preference, verdict normalization, and successful capture remain intact. A valid report plus nonzero exit preserves the report and failure code.
- [ ] The parent checks exit status and verdict, distinguishes the three limit classes, and neither retargets nor asks spawn to sleep until reset.
- [ ] `bash tests/spawn_test.sh` passes during implementation; prose-only spec delivery does not claim that these implementation gates already pass.

### S1+S2 follow-on gates

- [ ] IDs and backend/cwd binding are captured before completion when available; no-persist flags are removed only with the persistence slice.
- [ ] Two jobs sharing one project resume their respective exact IDs; last-session selectors are never used.
- [ ] The parent wait record survives yielding, and continuation receives only short `resume.md` with explicit checkpoint/output paths and the worker fence.
- [ ] Missing/wrong IDs, unavailable sessions, cwd mismatch, and rejected exact resume block without silently creating a thread. Original attempt artifacts remain available.
- [ ] Backend-specific persistence and exact-resume behavior are verified before each backend is declared supported; report capture and CLI exit semantics remain those of S0.

## Unverified

Exact Grok/agy quota diagnostic strings and their mapping to subscription window, transient 429, or credits/spend remain unverified. Obtain fixtures when available; do not block the generic S0 repair on them. Backend ID extraction and exact-resume invocation details are follow-on implementation verification gates, not open product choices. No other product decision is open.
