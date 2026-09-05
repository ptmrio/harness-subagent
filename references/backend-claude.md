# Backend: Claude Code

Read this after the user (or config) selected Claude. Official headless: `claude -p` / `--print`. Do **not** default `--bare` (it skips subscription login; needs `ANTHROPIC_API_KEY`).

Parents must spawn via [scripts/spawn.sh](../scripts/spawn.sh) (`--backend claude --mode review|implement`). Do not assemble these flags in PowerShell.

The script feeds the brief as **file stdin** (`< "$RUN/brief.md"`). Multiline argv to `claude.exe` on Windows arrives empty (`Input must be provided either through stdin or as a prompt argument`). Do not also redirect `/dev/null` onto that stdin. Do not pass `"$(cat brief)"` as an argument.

| Part | Why |
|---|---|
| `-p` | Headless one-shot. Without it you get the TUI. |
| `--permission-mode auto` | Classifier verifies, then allows. Review still omits Edit/Write in `--tools`. |
| `--tools` | Review: `Bash,Read,Glob,Grep` (Bash is how Review writes `report.md` / temp files). Implement adds `Edit,Write`. |
| `--model opus` | Skill policy default (series alias) unless the user or config pins. |
| `--effort xhigh` | `low` `medium` `high` `xhigh` `max`. |
| `--session-id "$SID"` | Fresh launch: preassigned lowercase UUID, saved before launch. Persistence remains enabled. |
| `--add-dir "$RUN"` | Lets Read/Bash see the brief/screenshots and write `report.md` outside the project tree. |
| `--append-system-prompt …` | Spawn script requires writing `report.md` before cleanup (final `-p` text is **last turn only**). |

**Optional Fable:** utterance `Fable` (or config / `--model`) pins `--model fable`. On Claude Code **≥2.1.255** that alias is Fable 5.1; below it still resolves to Fable 5 with no error. Version pin: `claude-fable-5-1` (fails loud on older CLIs). `claude-fable-5` is the **older** Fable 5, not 5.1. Do not pass `best` (silent Fable upgrade). Headless `-p` never shows Fable’s usage-credit consent prompt — it bills if the account would. Classifier fallback can move a Fable child onto Opus mid-run; that is vendor routing, not a sticky-route failure. Bracketed context aliases (`fable[1m]`) fail `spawn.sh` charset. Official: [Model configuration](https://code.claude.com/docs/en/model-config), [Fable 5.1](https://platform.claude.com/docs/en/models/fable-5-1/overview) (accessed 2026-09-05).

`scripts/spawn.sh` exports `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` so the child cannot nest Claude Agent spawns ([official](https://code.claude.com/docs/en/sub-agents): `"1"` disables nesting). Do not raise it for an L2 worker.

Images: name paths in the brief. `spawn.sh --image` is ignored for Claude. Copy screenshots into `$RUN`.

## Capture hardening

Claude `-p --output-format text` emits only the **final assistant message**. A cleanup turn after a good visual report will overwrite stdout. Mitigations in `spawn.sh`:

1. Child must write `$RUN/report.md` (brief + append-system-prompt).
2. Raw stdout lands in `$RUN/stdout.md`.
3. `finalize_capture` prefers `report.md` when it contains `VERDICT`, else stdout → `$RUN/last.md`.
4. Returned nonzero CLI exits still finalize and retain their exit status. Bold `**VERDICT` / `VERDICT:` normalize. When selected text has no verdict, scan raw stdout and stderr before handling empty output. Limit diagnostics become `VERDICT — BLOCKED: usage/rate limit` with `capture-status.txt=usage-limit`, labeled sources, and reset/retry evidence. Valid selected verdicts retain precedence.

Done means the process exited and capture artifacts exist. Success additionally requires the CLI exit status and report verdict to support success. Read `last.md`, `capture-status.txt`, and process status together; `ok` / `ok-report` describe capture, not job success. A valid report with a nonzero exit requires parent review. Generic non-limit errors remain `no-verdict` failures.

For `usage-limit`, inspect preserved stdout/stderr evidence. Subscription/session exhaustion: parent waits for the stated reset, retaining timezone. Transient 429 / Too Many Requests without stronger spend/quota evidence: short backoff, honoring retry hints. Insufficient credits, spend caps, or exhausted paid quota: ask the human before enabling spend; explicit spend evidence overrides generic 429. Ambiguous quota without reliable cause/reset: report evidence and ask once. Do not invent timing, purchase credits, or retry indefinitely. Keep backend/model and route pins sticky and stop dependent stages; spawn does not sleep or launch a sleeper. Exception: a `no-verdict` same-family / “which harness” ask is a nesting leak — rewrite the identity fence, relaunch **once**, same backend (see SKILL.md).

If a gate needs a host binary Git Bash / `--tools` cannot run (e.g. `powershell.exe` on native Windows), the **parent** runs it or the finding stays UNVERIFIED.

Persistence: `session-id` and `session.json` bind the native `session_id`, resolved cwd, originating/attempt run, mode, model, and effort. `preassigned: true` records intent, not proof of provider persistence. If `CLAUDE_CODE_SKIP_PROMPT_HISTORY` is set (even empty), spawn records persistence unavailable and leaves the environment unchanged. Python 3 (`python` or `python3`) is checked for JSON metadata; UUID generation tries `uuidgen`, Python uuid4, then PowerShell `[guid]::NewGuid()`. Dry-run prints a planned ID without publishing identity files or starting Claude.

Exact resume: parent follows SKILL.md's wait/checkpoint protocol, copies the two identity records to a separate attempt, and writes a short continuation to that attempt's `brief.md`. `spawn.sh --resume-id "$SID"` validates records/cwd/route/role and emits `--resume "$SID"` instead of `--session-id`. It re-passes `-p`, permission-mode, tools, model, effort, `--add-dir "$RUN"`, and append-system-prompt; the continuation remains file stdin. No `--continue`, bare `--resume`, or `--fork-session`. Missing/mismatched ID or disabled history blocks before launch. Provider rejection is nonzero/BLOCKED, never a fresh-thread retry. Keep the original report in its original slot and write the new complete report before cleanup.
