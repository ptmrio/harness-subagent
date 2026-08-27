# User config

Optional per-user routing. Lives **outside** the skill directory so `npx skills add` / git pull cannot overwrite it and so each agent install does not get its own drifting copy.

## Path

1. `$HARNESS_SUBAGENT_CONFIG` — if this env var is **set**, that path is the only file. If it is missing, **ask once** (fail closed; do not walk the rest).
2. Else `${XDG_CONFIG_HOME:-$HOME/.config}/harness-subagent/config.toml`

Recommended create path on every OS, including Windows: `~/.config/harness-subagent/config.toml` (`$HOME` is `%USERPROFILE%` in PowerShell).

Do not also search `%APPDATA%`. One file. Missing file = utterance or ask once (today’s behavior).

Copy [assets/config.example.toml](../assets/config.example.toml). Do **not** auto-create. When the user says “always use Codex for review” or “always use Opus for UI” (or pins models), offer to write this file, then write it only if they confirm. Example values are **suggestions**, not protocol.

## Schema

TOML. Values must be allowlisted tokens (no `$`, backticks, `;`, spaces, or paths). Backend values: `claude` | `codex` | `grok` | `cursor` | `gemini` | `opencode` | `droid`. Self-class values (parent does the job; do not spawn): `self` | `orchestrator` | `parent` | `you`. Canonical: `self`. If the value is unknown, or a backend binary is missing, ask once. Self-class is never “missing binary.”

Key names: `^[a-z][a-z0-9_-]*$` (hyphens allowed).

### Known `defaults` keys (parent may infer)

Prefer the more specific key when the job matches, in this order:

1. `*-ui` / `code-review-visual` over their non-ui / non-visual twins (if `*-ui` is unset, fall back to the twin, then continue).
2. `writer` over `implement` when the deliverable is **sustained text** (README, SKILL.md copy, GitHub About, article) — not a code slice that happens to include comments.
3. `research` over `code-review-*` when there is **no diff / code-change under review** (external lookup, competitive landscape, current vendor docs, GitHub inventory). “Is this diff correct?” is `code-review-task`, not `research`.
4. `implement-ui` still beats `writer` for UI screens.

| Key | When | `spawn.sh --mode` |
|---|---|---|
| `spec` | Write or refine a spec / design (not UI-shaped). | `implement` |
| `spec-ui` | Same, for layout / interaction / screens. | `implement` |
| `plan` | Write or refine an implementation plan (not UI-shaped). | `implement` |
| `plan-ui` | Same, for a UI slice. | `implement` |
| `implement` | Ship a bounded slice that is **not** UI/UX. | `implement` |
| `implement-ui` | Ship UI/UX: layout, interaction, CSS, screens. | `implement` |
| `writer` | Sustained prose: README, SKILL.md copy, GitHub About/topics, articles. Alias: `docs` (the **key name**, not the English word in “current docs”). | `implement` |
| `research` | External lookup, competitive landscape, current vendor docs, GitHub inventory. Alias: `researcher`. | `review` |
| `code-review-task` | Ordinary diff / correctness review. | `review` |
| `code-review-adversarial` | Pressure-test; assume it is flawed. Alias: `code-review-adverserial`. | `review` |
| `code-review-visual` | Live UI or screenshots (Playwright / browser MCP allowed). | `visual` |

Aliases (same lookup as the target): `review` → `code-review-task`; `ui` → `implement-ui`; `ux` / `ui-ux` → `implement-ui`; `docs` → `writer`; `researcher` → `research`.

The **skill** still has no author job→harness map. These keys are the **user** speaking in advance. `assets/config.example.toml` is a suggestion (`writer = "grok"` there); copy and change it.

`code-review-visual`: do **not** put “forbid a browser stack” in the brief. Name Playwright (or the parent’s shots). Codex: `spawn.sh --mode visual` and `--image` per screenshot. Claude/Grok: `--mode visual` runs as Review (brief: do not edit application files); shots via `--add-dir` / named paths.

### Self-class values

If the matched key’s value is `self`, `orchestrator`, `parent`, or `you`: **do not spawn**. Do the job in this session. Do not ask which harness. Do not apply the parent-family skip (self-class is not a backend).

Do **not** treat a parent-family backend as self. `writer = "grok"` while the parent is Grok still skips and asks once. Pin `self` when the orchestrator should do that job. Name `grok` this turn if you want Grok Build spawned from a Grok parent.

Same for Cursor: `implement = "cursor"` while the parent is Cursor Agent / `cursor-agent` / Grok Bot still skips and asks once. Pin `self` (or `orchestrator` / `parent` / `you`) when this session should do that job. Name `cursor-agent` this turn only if you intend to spawn Cursor’s CLI from a *different* family parent (and then use [more-clis.md](more-clis.md); it is not in `spawn.sh`).

Pass self-class only in the TOML (or when this utterance says the parent should do it). Never `spawn.sh --backend self`.

### Extra `defaults` keys (not inferred)

Any other matching key is a **named label**. The parent uses it only when this utterance contains that label. It must **not** invent keys. `writer` / `research` are known keys above, not extra labels. Config fixtures in evals are test setup, not labels the user spoke.

Unknown `[models]` / `[effort]` keys for extra CLIs are optional; those backends still need [more-clis.md](more-clis.md).

## Routing

1. This utterance — named harness, pinned model id, **or** parent-should-do-it this turn (“you do it”, “don’t spawn”, “stay here”).
2. This file — pick the matching known key (or a named extra key the user said). If the value is self-class, stop: do the job here. Else **skip any backend that is the parent’s own family**. If nothing remains, ask once.
3. Ask once.

The README author table is not this file. Do not copy it in unless the user asked to pin those as *their* defaults.

Pass pinned `[models]` / `[effort]` into `scripts/spawn.sh` as `--model` / `--effort` (the script allowlists the charset). Never interpolate TOML into a shell string with `eval` or unquoted expansion.
