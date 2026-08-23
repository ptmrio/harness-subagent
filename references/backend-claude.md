# Backend: Claude Code

Read this after the user (or config) selected Claude. Official headless: `claude -p` / `--print`. Do **not** default `--bare` (it skips subscription login; needs `ANTHROPIC_API_KEY`).

Parents must spawn via [scripts/spawn.sh](../scripts/spawn.sh) (`--backend claude --mode review|implement`). Do not assemble these flags in PowerShell.

The script feeds the brief as **file stdin** (`< "$RUN/brief.md"`). Multiline argv to `claude.exe` on Windows arrives empty (`Input must be provided either through stdin or as a prompt argument`). Do not also redirect `/dev/null` onto that stdin. Do not pass `"$(cat brief)"` as an argument.

| Part | Why |
|---|---|
| `-p` | Headless one-shot. Without it you get the TUI. |
| `--permission-mode plan` | Official: explore, no source edits. |
| `--permission-mode acceptEdits` | Unattended Implement; still not full bypass. |
| `--tools` | Review: `Bash,Read,Glob,Grep`. Implement adds `Edit,Write`. |
| `--model opus` | Series alias unless the user or config pins. |
| `--effort xhigh` | `low` `medium` `high` `xhigh` `max`. |
| `--no-session-persistence` | One-shot; do not clutter resume history. |
| `--add-dir "$RUN"` | Lets Read see the brief/screenshots outside the project tree. |

Optional: `--append-system-prompt 'First line of your final report must be: VERDICT — …'`. Images: name paths in the brief.

If `last.md` is `You've hit your session limit`, do **not** relaunch Claude immediately — switch backend or wait for the stated reset.
