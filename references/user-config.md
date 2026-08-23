# User config

Optional per-user routing. Lives **outside** the skill directory so `npx skills add` / git pull cannot overwrite it and so each agent install does not get its own drifting copy.

## Path

1. `$HARNESS_SUBAGENT_CONFIG` — if this env var is **set**, that path is the only file. If it is missing, **ask once** (fail closed; do not walk the rest).
2. Else `${XDG_CONFIG_HOME:-$HOME/.config}/harness-subagent/config.toml`

Recommended create path on every OS, including Windows: `~/.config/harness-subagent/config.toml` (`$HOME` is `%USERPROFILE%` in PowerShell).

Do not also search `%APPDATA%`. One file. Missing file = utterance or ask once (today’s behavior).

Copy [assets/config.example.toml](../assets/config.example.toml). Do **not** auto-create. When the user says “always use Codex for review” or “always use Opus for UI” (or pins models), offer to write this file, then write it only if they confirm.

## Schema

TOML. Values must be allowlisted tokens (no `$`, backticks, `;`, spaces, or paths). Backend values: `claude` | `codex` | `grok` | `cursor` | `gemini` | `opencode` | `droid`. If the value is unknown, or the binary is missing, ask once.

Key names: `^[a-z][a-z0-9_-]*$` (hyphens allowed).

### Known `defaults` keys (parent may infer)

Prefer the more specific key (`*-ui`, `code-review-visual`) when the job matches. If `*-ui` is unset, fall back to the non-ui twin, then ask once.

| Key | When | `spawn.sh --mode` |
|---|---|---|
| `spec` | Write or refine a spec / design (not UI-shaped). | `implement` |
| `spec-ui` | Same, for layout / interaction / screens. | `implement` |
| `plan` | Write or refine an implementation plan (not UI-shaped). | `implement` |
| `plan-ui` | Same, for a UI slice. | `implement` |
| `implement` | Ship a bounded slice that is **not** UI/UX. | `implement` |
| `implement-ui` | Ship UI/UX: layout, interaction, CSS, screens. | `implement` |
| `code-review-task` | Ordinary diff / correctness review. | `review` |
| `code-review-adversarial` | Pressure-test; assume it is flawed. Alias: `code-review-adverserial`. | `review` |
| `code-review-visual` | Live UI or screenshots (Playwright / browser MCP allowed). | `visual` |

Aliases (same lookup as the target): `review` → `code-review-task`; `ui` → `implement-ui`; `ux` / `ui-ux` → `implement-ui`.

The **skill** still has no author job→harness map. These keys are the **user** speaking in advance.

`code-review-visual`: do **not** put “forbid a browser stack” in the brief. Name Playwright (or the parent’s shots). Codex: `spawn.sh --mode visual` and `--image` per screenshot. Claude/Grok: `--mode visual` runs as read-only review; shots via `--add-dir` / named paths.

### Extra `defaults` keys (not inferred)

Any other matching key is a **named label**. The parent uses it only when this utterance contains that label. It must **not** guess `docs` from “write a README.”

Unknown `[models]` / `[effort]` keys for extra CLIs are optional; those backends still need [more-clis.md](more-clis.md).

## Routing

1. This utterance (named harness or pinned model id).
2. This file — pick the matching known key (or a named extra key the user said). **Skip any backend that is the parent’s own family**. If nothing remains, ask once.
3. Ask once.

The README author table is not this file. Do not copy it in unless the user asked to pin those as *their* defaults.

Pass pinned `[models]` / `[effort]` into `scripts/spawn.sh` as `--model` / `--effort` (the script allowlists the charset). Never interpolate TOML into a shell string with `eval` or unquoted expansion.
