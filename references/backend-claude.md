# Backend: Claude Code

Read this after the user (or config) selected Claude. Official headless: `claude -p` / `--print`. Do **not** default `--bare` (it skips subscription login; needs `ANTHROPIC_API_KEY`).

Parents must spawn via [scripts/spawn.sh](../scripts/spawn.sh) (`--backend claude --mode review|implement`). Do not assemble these flags in PowerShell.

The script feeds the brief as **file stdin** (`< "$RUN/brief.md"`). Multiline argv to `claude.exe` on Windows arrives empty (`Input must be provided either through stdin or as a prompt argument`). Do not also redirect `/dev/null` onto that stdin. Do not pass `"$(cat brief)"` as an argument.

| Part | Why |
|---|---|
| `-p` | Headless one-shot. Without it you get the TUI. |
| `--permission-mode auto` | Classifier verifies, then allows. Review still omits Edit/Write in `--tools`. |
| `--tools` | Review: `Bash,Read,Glob,Grep` (Bash is how Review writes temp files). Implement adds `Edit,Write`. |
| `--model opus` | Series alias unless the user or config pins. |
| `--effort xhigh` | `low` `medium` `high` `xhigh` `max`. |
| `--no-session-persistence` | One-shot; do not clutter resume history. |
| `--add-dir "$RUN"` | Lets Read see the brief/screenshots outside the project tree. |

Optional: `--append-system-prompt 'First line of your final report must be: VERDICT — …'`. Images: name paths in the brief.

`spawn.sh --image` is ignored for Claude. Copy screenshots into `$RUN`; `--add-dir "$RUN"` is already on the argv. If a gate needs a host binary Git Bash / `--tools` cannot run (e.g. `powershell.exe` on native Windows), the **parent** runs it or the finding stays UNVERIFIED.

If `last.md` is `You've hit your session limit`, do **not** relaunch Claude immediately — switch backend or wait for the stated reset.
