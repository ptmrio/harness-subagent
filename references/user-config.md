# User config

Optional per-user routing. Lives **outside** the skill directory so `npx skills add` / git pull cannot overwrite it and so each agent install does not get its own drifting copy.

## Path

1. `$HARNESS_SUBAGENT_CONFIG` — if this env var is **set**, that path is the only file. If it is missing, **ask once** (fail closed; do not walk the rest).
2. Else `${XDG_CONFIG_HOME:-$HOME/.config}/harness-subagent/config.toml`

Recommended create path on every OS, including Windows: `~/.config/harness-subagent/config.toml` (`$HOME` is `%USERPROFILE%` in PowerShell).

Do not also search `%APPDATA%`. One file. Missing file = utterance or ask once (today’s behavior).

Copy [assets/config.example.toml](../assets/config.example.toml). Do **not** auto-create. When the user says “always use Codex for review” (or pins models), offer to write this file, then write it only if they confirm.

## Schema

TOML. Unknown keys are ignored. Values must be allowlisted tokens (no `$`, backticks, `;`, spaces, or paths in `defaults.*` / `models.*` / `effort.*`).

```toml
[defaults]
review = "codex"       # adversarial / critical / visual / unstuck when the user did not name a harness
implement = "claude"

[models]
claude = "opus"
codex = "gpt-5.6-sol"
grok = "grok-4.6"
# cursor / gemini / opencode / droid: optional; extra CLIs still need references/more-clis.md

[effort]
claude = "xhigh"
codex = "xhigh"
grok = "xhigh"
```

`defaults.review` / `defaults.implement` values: `claude` | `codex` | `grok` | `cursor` | `gemini` | `opencode` | `droid`. If the value is unknown, or the binary is missing, ask once.

## Routing

1. This utterance (named harness or pinned model id).
2. This file — **skip any backend that is the parent’s own family**. If nothing remains, ask once.
3. Ask once.

The README author table is not this file. Do not copy it in unless the user asked to pin those as *their* defaults.

Pass pinned `[models]` / `[effort]` into `scripts/spawn.sh` as `--model` / `--effort` (the script allowlists the charset). Never interpolate TOML into a shell string with `eval` or unquoted expansion.
