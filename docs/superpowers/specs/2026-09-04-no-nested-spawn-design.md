# No nested spawn (L1 vs L2 command fence)

**Status:** approved for implement (operator asked full loop this turn)  
**Date:** 2026-09-04  
**Repo:** `ptmrio/harness-subagent`  
**Trigger:** WSL Session Ad Creation — Cursor spawned Codex visual (`20260904-ad-visual2`). Codex loaded `harness-subagent`, treated itself as parent, saw `code-review-visual = codex`, wrote same-family ask. `capture-status: no-verdict`. Dual Codex install was unrelated.

## Practices (dated)

1. **Anthropic — Claude Code sub-agents** ([sub-agents](https://code.claude.com/docs/en/sub-agents), accessed 2026-09-04). Nested subagents exist; default depth can be three layers. Set `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` to `"1"` to **disable nesting**. Omit/`disallow` the Agent tool to stop a given child from spawning. Nesting is a budget, not a default we want for a one-shot cross-CLI worker.
2. **OpenAI — Codex exec + spawn_agent** ([codex exec](https://github.com/openai/codex) is non-interactive one-shot; `spawn_agent` spec in `codex-rs/core/src/tools/handlers/multi_agents_spec.rs`, accessed 2026-09-04). Do **not** spawn sub-agents unless the user / AGENTS.md / **skill instructions explicitly ask**. Requests for thoroughness do not count. `codex exec` is the one-shot we already wrap.

**Conflict:** vendors now ship in-process nesting. This skill is still **one-shot cross-CLI dispatch**. A child that re-enters this skill is accidental re-orchestration, not planned fan-out. Prefer modern isolation knobs (`depth=1`, no Agent, brief that does not authorize spawn) over copying vendor nested-by-default.

## Problem

L1 (orchestrator) vocabulary leaked into the L2 brief:

```
Role: `code-review-visual`. Spawn `--mode visual`.
```

Codex has this skill installed globally. “Spawn `--mode visual`” matched the skill description. The child ran the parent protocol and same-family-skipped itself.

`visual3` recovered by opening with `YOU ARE THE REVIEWER. DO NOT SPAWN` and forbidding `harness-subagent` / `spawn.sh`. That is the proof the fence works.

## Command levels (normative)

| Level | Who | May use | Must never treat as own |
|---|---|---|---|
| **L0** | Human | `/harness-subagent`, “orchestrate”, named harness, pin `self` | `spawn.sh` flags |
| **L1** | Parent that loaded this skill | `scripts/spawn.sh --backend --mode`, config routing, same-family skip, ask once, Superpowers dispatchers, synthesize | Pasting `Spawn --mode …` **into the brief**; asking the child which harness |
| **L2** | CLI launched by `spawn.sh` | Role card Superpowers only, Playwright / named shots, `report.md`, app edits only if Implement | `harness-subagent`, `spawn.sh`, `requesting-code-review`, “which harness?”, same-family ask, in-process `spawn_agent` / Agent tool for another CLI |

`Spawn --mode visual` was the leaked L1 token in visual2. L1 invokes `scripts/spawn.sh --mode …`. That argv is **not** a child instruction.

## Design

Three layers. All three ship; none is optional.

### 1. Brief identity fence (protocol — catches visual2)

Every child brief **starts** with the fence from `roles.md` (fixed wording). Parent paste rule: never put `scripts/spawn.sh` or `--mode …` in the brief. Spawn mode lives in [user-config.md](../../references/user-config.md), not on the role cards.

If `last.md` is a same-family / “which harness” ask (`no-verdict`, no `VERDICT`): **nesting leak**. Rewrite fence, relaunch **once**, **same** backend. Do not retarget (sticky). Same shape as unbounded-git visual relaunch.

### 2. Skill matcher (so L2 does not load this skill)

YAML `description` and a SKILL.md red-flag: do **not** use this skill if `HARNESS_SUBAGENT_RUN` is set or the prompt says `YOU ARE THE WORKER`. Do the briefed job.

### 3. Mechanical (spawn.sh)

- If `HARNESS_SUBAGENT_RUN` is already set, die `nested spawn refused` (no same-run carve-out; parent relaunch arrives with the var unset).
- `export HARNESS_SUBAGENT_RUN="$RUN"` for the child process.
- `export CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` so Claude L2 cannot nest Agent (official knob). Do not add Codex `--disable multi_agent_v2` (untested; fence + OpenAI “don’t spawn unless asked” is enough).

## Non-goals

- Changing user-config defaults (`code-review-visual = "codex"` stays valid when L1 is Cursor).
- Treating same-family skip as a bug — it is correct **for L1**. Wrong only when L2 runs it.
- Recursive planned fan-out inside this skill.
- Pinning `self` for visual as the only fix (that would drop independent Codex visual from Cursor).

## Files

| File | Change |
|---|---|
| `SKILL.md` | Description child-exclusion; L1/L2 section; paste rule; red flags; relaunch-once |
| `references/roles.md` | Fence; parent-spawn vs paste; must-not harness-subagent on every card |
| `scripts/spawn.sh` | Nest refuse + env exports |
| `tests/spawn_test.sh` | Nested die; child env |
| `evals/evals.json` | Visual brief fence; same-family last.md → relaunch once |
| `README.md` | One-shot child does not re-orchestrate |
| `references/backend-claude.md` | Depth=1 is set by spawn.sh |

## Acceptance

- Parent visual brief contains the fence and does **not** contain `Spawn --mode`.
- Child with `HARNESS_SUBAGENT_RUN` set does not call `spawn.sh` (mechanical die if it does).
- Replay of visual2 last.md → parent relaunches Codex once with fence, does not retarget, does not invent a verdict.
- `bash tests/spawn_test.sh` green.
