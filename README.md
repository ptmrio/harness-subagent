# harness-subagent

Delegate a bounded task to another coding-agent CLI. You stay the parent. The child returns a report. You judge it.

CLIs: Claude Code, Codex, Grok Build, Antigravity (`agy`), and the Cursor CLI (`cursor-agent`).

Spoken model names and token prices are in `references/models.md`. The host chooses the CLI, the model, and the effort. This repo does not rank jobs.

```bash
npx skills add ptmrio/harness-subagent -g
```

```text
scripts/spawn.sh --model Astra --project <app> --run <temp-dir>
scripts/health.sh
scripts/health.sh --update
```

On Windows, run `scripts/spawn.sh` with Git Bash and pass the script path as an argument. Do not build the command inside a PowerShell double-quoted string.

A usage limit with a reset time within 24 hours waits, then resumes that same session once. Any other stop leaves the report in the run directory and does not switch CLI.
