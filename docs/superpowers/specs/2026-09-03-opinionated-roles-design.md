# Opinionated roles + Superpowers-by-default

**Status:** approved — implemented 2026-09-03; **roles.md + SKILL.md are canonical** (this file is historical). Patch **v0.2.1** addressed adversarial review findings (TDD paste, role contracts, exact Superpowers names, orchestrate precedence, Grok shots, sticky stops downstream stages, alias resolution, evals).  
**Date:** 2026-09-03  
**Repo:** `ptmrio/harness-subagent`

## Problem

Harness-subagent briefs are protocol-strong but role-thin. Review is split into soft “task” vs “adversarial.” Visual is change-scoped. Implement inherits Superpowers’ TDD theater risk. Subagent briefs currently say **do not** load Superpowers, while we expect every target harness to have them. Orchestration (“orchestrate this”) does not yet encode a coherent multi-step loop.

## Goals

1. Opinionated **role cards** (heavy + light) that shape every brief.
2. **Superpowers by default** as role-relevant skills — never a full parent workflow restart in the child.
3. **Orchestrate** utterance starts practices → implement → validate → final coherence; single sub-agent asks stay one-shot.
4. **Orchestrator voice:** CTO-level (brief, bullets, ASCII); stay aligned with the human operator; never swap backend/model when the child hits usage/rate limits.

## Non-goals

- No `spawn.sh` behavior change (docs-only unless a mode string needs clarifying).
- No bundling or installing Superpowers inside this skill.
- No auto multi-harness fan-out; still one harness per question unless asked.
- No replacing poteto/pstack — borrow ideas only (laziness, prove-it-works, interrogate posture, own the subagent’s work).

## Architecture

| File | Role |
|---|---|
| `SKILL.md` | Spawn protocol, orchestrate checklist, sticky-route, orchestrator voice, brief skeleton, postures **index** → roles.md |
| `references/roles.md` | **New** — full role cards |
| `references/user-config.md` | Canonical `code-review` + aliases; prefer-order |
| `assets/config.example.toml` | Example uses `code-review` |
| `README.md` | Orchestrate vs one-shot; opinionated roles summary |
| `evals/evals.json` | Alias merge, orchestrate vs one-shot, no limit-fallback |

Shared brief rules (all roles):

1. Paste the matching card’s **Superpowers map** (named skills only). Forbid running `using-superpowers` as a controller restart (no re-brainstorm / re-plan of the user’s product work).
2. Keep the five-part brief: Objective / Where / Tried / Change-my-mind / Return format.
3. Parent synthesizes; child is not an oracle.
4. Write policy unchanged: Review / Visual / Research = no app edits; Implement / Spec / Plan / Writer = allowlisted paths only.

## Config routing

- Canonical key: **`code-review`** (adversarial + cleanliness + correctness).
- Aliases → same card: `code-review-task`, `code-review-adversarial`, `review`.
- Lookup when resolving the review backend: `code-review` if set; else `code-review-adversarial`; else `code-review-task`; else `review`. If more than one of these is set to **different** backends, **ask once** (do not silently pick).
- Prefer-order unchanged in spirit: `code-review-visual` beats `code-review` for UI confirm; `research` beats review when there is no diff under review; `writer` / `*-ui` rules stay as today.
- Example config drops separate task/adversarial lines (aliases documented in user-config).

## Orchestrate vs one-shot

### Orchestrate (multi-step)

**Triggers (any):** user says orchestrate / orchestration / “run the full loop” / multi-step handoff that names practices+implement+review together. **Not** triggers: a single named harness or single job (“ask Codex to review”, “have Claude implement only …”).

Parent checklist (skip steps already done or user-waived; **one job per spawn**):

1. **Practices** — Research (or parent `self` if pinned): gather **exactly two** current best-practice anchors — one from **Anthropic** and one from **OpenAI** official guidance. Optionally **supplement** (not replace) with Cursor and/or xAI when the stack or harness makes them relevant. Cite + date-stamp. Prefer official docs over secondary summaries.
2. **Implement** — bounded slice against those practices and the brief. TDD policy table applies.
3. **Validate** — `code-review` (adversarial). Add `code-review-visual` when UI is in play.
4. **Final coherence** — parent default `self` (or one short Review spawn): logic, redundancy, overall sanity vs the two practice anchors and the original ask. CTO bullets + ASCII when useful. Align with the human before calling done if product preference is still ambiguous.

Per-spawn sticky route: if the child hits usage/rate limits (or any soft failure that tempts a swap), **do not** retarget another backend or model. Report failure, mark UNVERIFIED / blocked, ask once.

### One-shot

Utterance names a harness or a single job (“ask Codex to review this diff”) → one brief, one spawn, synthesize. **Do not** auto-chain the full orchestrate loop.

## Heavy role cards

### `code-review`

- **Mission:** Assume the change is flawed. Hunt correctness bugs **and** overkill, inconsistencies, dirty hacks, best-practice drift, and tests that do not protect long-term behavior.
- **Must:** Rank by severity; each finding has `file:line` + concrete failure (or concrete maintainability failure). Prefer deletion/simplification. Call out vacuous tests. “Reject this approach” may be a top finding.
- **Must not:** Style nits with no cost; invent issues outside named scope; edit application files.
- **Superpowers map:** Adapt `requesting-code-review` / quality bar only. No brainstorm→plan restart. Systematic-debugging only if diagnosing a claimed bug.
- **Return:** VERDICT / FINDINGS / UNVERIFIED.

### `code-review-visual`

- **Mission:** Component review of the change **plus** holistic walk of relevant pages as a real user. Default identity = user-walk; screenshots-only is fallback when no browser (gaps → UNVERIFIED).
- **Must:** Navigate primary flows on affected surfaces; flag counter-intuitive UX, over-complicated UI, visual drift from modern norms / the project’s design language; ground claims in shots or live evidence + named CSS/JS.
- **Must not:** Invent a browser stack when none exists; edit app files; treat one screenshot as a full pass.
- **Superpowers map:** verification-before-completion on the real UI; no workflow restart.
- **Return:** Same triad; split FINDINGS into **Change** vs **Holistic UX** when both apply.

### `implement` / `implement-ui`

- **Mission:** Ship the briefed slice. TDD by default for useful long-term contracts — not for everything.
- **TDD policy table:**
  - **Required:** new/changed behavior, bug fixes, non-trivial refactors that can regress.
  - **Forbidden:** string-presence / grep-style tests on prose or prompts; tests that cannot name the production change that would fail them; “test everything” scaffolding.
  - **Optional / skip with one-line why in GATES:** copy/text tweaks, pure config, renames, generated output, throwaway prototypes.
- **Must:** Allowlisted paths only; run named gates; prove on the real artifact (`implement-ui`: exercise the UI path when feasible).
- **Must not:** Expand scope; push; write ceremony tests for TDD theater.
- **Superpowers map:** `test-driven-development` + `verification-before-completion` per the table; no brainstorm/plan reload.
- **Return:** VERDICT / DONE / GATES / UNVERIFIED (GATES includes skip reasons).

### `research`

- **Mission:** Current, authoritative answers; modern best practice over stale orthodoxy.
- **Source ranking:** (1) official current docs / release notes, (2) primary vendor blogs & GitHub, (3) recent high-signal practitioner writeups. Demote undated blogspam / superseded or materially outdated sources unless nothing else exists — mark age.
- **Must:** When modern practice conflicts with legacy standard, name the conflict and recommend modern unless project constraints force legacy; date-stamp sources.
- **Must not:** Treat random Medium/SO as peer to official docs; invent API surface.
- **Superpowers map:** none (docs/web tools only); no TDD/review dispatcher; no workflow restart.
- **Return:** VERDICT / ANSWER (citations) / UNVERIFIED.

## Light role cards

| Role | Voice |
|---|---|
| **Spec / Spec-ui** | YAGNI; 2–3 alternatives; lock scope before code. Brainstorming-shaped skills only; no full re-chain in child. |
| **Plan / Plan-ui** | Junior-proof tasks; each step has a verification gate; no verbatim scaffolding that fights the toolchain. |
| **Writer** | Sustained prose; unslop / technical-writing bar; no fake citations. |
| **Unstuck** | Independent diagnosis; don’t inherit parent’s theory; reproduce first; root cause before fix suggestions. |

(Unstuck remains a posture; no new required config key in this change.)

## Orchestrator output (always)

- CTO-level: brief, concise, bullet points, ASCII previews/diagrams when they beat prose.
- Stay on the same page with the human operator: surface assumptions; ask on irreversible actions and unsettled product preferences; do not silently invent scope.
- Post-spawn report shape unchanged: what was asked → harness verdict → agree/disagree → recommendation.

## Research backdrop (informing the design)

Common Superpowers pain points this design absorbs:

- Ceremony that doesn’t scale → orchestrate is opt-in via wording; one-shot stays cheap.
- TDD over-application / vacuous tests → Implement TDD table + adversarial review of useless tests.
- Subagent bootstrap loops (#2160-class) → named skills only; forbid full `using-superpowers` controller restart.
- Silent stalls / stop-happy plan execution → prefer continuous completion of the briefed job; parent does not swap models mid-failure.

Poteto/pstack ideas borrowed: laziness / subtract-before-add in review; prove on the real artifact; “no is acceptable”; parent owns synthesis.

## Success criteria

- “Orchestrate …” runs practices → implement → review → coherence; “ask X to review” stays one-shot.
- Review brief is adversarial/cleanliness, not soft correctness-only; config aliases resolve to one card.
- Visual defaults to user-walk; screenshot fallback documented.
- Implement brief carries the TDD required/forbidden/optional table.
- Child briefs name relevant Superpowers skills and forbid full workflow restart.
- Limit/usage failure does not retarget backend/model.
- Orchestrator output matches CTO voice + human alignment.

## Implementation notes (for writing-plans later)

1. Add `references/roles.md` from the cards above.
2. Patch `SKILL.md` (remove anti-Superpowers lines; add orchestrate checklist, sticky-route, voice, postures index).
3. Patch `user-config.md` + `config.example.toml` for `code-review` canonical + aliases.
4. README + evals updates.
5. No spawn.sh change unless documentation of `--mode` wording needs a one-line sync.
