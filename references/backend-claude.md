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
| `--no-session-persistence` | One-shot; do not clutter resume history. |
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
4. Bold `**VERDICT` / `VERDICT:` normalized; usage/session-limit text becomes `VERDICT — BLOCKED: usage/rate limit` with `capture-status.txt=usage-limit`.

If `capture-status.txt` is `usage-limit` or a generic `no-verdict`: do **not** relaunch Claude immediately and do **not** retarget backends (sticky route). Ask once / wait for the stated reset. Exception: a `no-verdict` same-family / “which harness” ask is a nesting leak — rewrite the identity fence, relaunch **once**, same backend (see SKILL.md).

If a gate needs a host binary Git Bash / `--tools` cannot run (e.g. `powershell.exe` on native Windows), the **parent** runs it or the finding stays UNVERIFIED.
