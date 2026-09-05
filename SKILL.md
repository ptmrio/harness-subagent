---
name: harness-subagent
description: >
  Use when the user asks to orchestrate, outsource, delegate, or hand off a
  slice to another coding-agent CLI as a one-shot subagent — Claude Code,
  Codex, Grok Build, Cursor Agent, Antigravity CLI, Gemini CLI, OpenCode, or Droid — or to ask
  Claude, ask GPT, ask Codex, ask Grok, ask Gemini, ask Fable, ask Astra, get a second opinion, or pressure-test
  a plan or diff from a different harness. Do not use to install those CLIs or
  to explain their flags. Do not use if this session was launched by this skill
  (prompt starts with YOU ARE THE WORKER, or HARNESS_SUBAGENT_RUN is set) — do
  the briefed job; do not spawn.
license: MIT
compatibility: Requires another coding-agent CLI on PATH (claude, codex, grok, agy, and/or cursor-agent). Windows, WSL, Linux, macOS. Git Bash on native Windows.
metadata:
  author: ptmrio
  version: "0.2.5"
---

# Harness Subagent

Dispatch **another coding-agent harness** as a one-shot subagent, then synthesize.

**Core principle: the harness is a subagent, not an oracle.** A model reviewing its own work reproduces its own blind spots. That worth is destroyed if you forward the answer without judging it.

**Orchestrator voice:** CTO-level — brief, concise, bullets, ASCII previews when they beat prose. Stay aligned with the human operator (surface assumptions; ask on irreversible actions and unsettled product preferences; do not silently invent scope).

**Sticky route:** If the child hits usage/rate limits (or any soft failure that tempts a swap), do **not** retarget another backend or model. Mark UNVERIFIED / blocked and preserve route pins. The parent owns waiting and retry decisions. For subscription/session exhaustion, wait for the stated reset, retaining timezone. For transient HTTP 429 / Too Many Requests without stronger spend/quota evidence, use short backoff and honor any retry hint. Insufficient credits, spend caps, or exhausted paid quota require asking the human before enabling spend; explicit spend evidence overrides generic 429. For ambiguous quota without a reliable cause/reset, report the evidence and ask once. Do not invent reset values, purchase credits, or retry indefinitely. Spawn does not sleep or launch a sleeper. Exception: a `no-verdict` same-family / “which harness” ask is a **nesting leak** — rewrite the identity fence, relaunch **once**, same backend; do not ask and do not swap. In a **full orchestrate loop**, stop dependent stages until the failed stage has a deliverable.

Do **not** pick a harness because of a task stereotype unless the **user config** has that key (see [references/user-config.md](references/user-config.md)). Routing order: **this utterance → user config → ask once.** Same protocol for every backend. Role personality and Superpowers maps: [references/roles.md](references/roles.md) (**canonical**).

Default to **Review** (do not edit application files). Allow application writes only when the user (or an approved plan) asks for Implement. Review and Visual may create temp files and write reports.

## Command levels (do not mix)

This skill is **one-shot**. The child must not re-enter it. Vendor CLIs may allow nested Agent/`spawn_agent`; that is not a license to run this protocol again.

| Level | Who | Commands | Forbidden as “yours” |
|---|---|---|---|
| **L0** | Human | `/harness-subagent`, “orchestrate”, named harness, pin `self` | `spawn.sh` flags |
| **L1** | Parent that loaded this skill | `scripts/spawn.sh --backend --mode`, config routing, same-family skip, ask once, synthesize | Putting spawn.sh invocations **in the brief**; asking the child which harness |
| **L2** | CLI `spawn.sh` launched | Role Superpowers only, Playwright / named shots, `report.md` | This skill, `spawn.sh`, `requesting-code-review`, “which harness?”, same-family ask |

L1 invokes `scripts/spawn.sh --mode …`. That argv is **not** a child instruction. If you are L2 (`HARNESS_SUBAGENT_RUN` set, or the prompt starts `YOU ARE THE WORKER`), **stop reading this spawn protocol** and do the briefed job.

`spawn.sh` exports `HARNESS_SUBAGENT_RUN` and sets `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`. A nested `spawn.sh` dies (var already set).

## Orchestrate vs one-shot

**Precedence (evaluate in order):**

1. **Single-job narrowing wins one-shot** — utterance names one job (second opinion, review this diff, implement only …, rewrite the README, research X) → one brief, one spawn. A leading “Orchestrate this —” does **not** force the full loop.
2. **Explicit full-loop wins** — user says “run the full loop” / names practices+implement+review together / open-ended “orchestrate this feature end-to-end” with **no** single-job noun → full checklist below. A named harness here only **pins the backend for each stage** (or per-stage config); it does **not** collapse the loop into one shot.
3. Otherwise ask once what they want (full loop vs one job).

**Full-loop checklist** (skip steps already done or user-waived; **one job per spawn**):

1. **Practices** — Research (or parent `self` if pinned): exactly **two** anchors — one Anthropic + one OpenAI official guidance. Optionally supplement (not replace) with Cursor/xAI when the stack/harness makes them relevant. Cite + date-stamp.
2. **Implement** — bounded slice against those practices. Paste the full TDD table from [roles.md](references/roles.md).
3. **Validate** — `code-review` (adversarial). Add `code-review-visual` when UI is in play.
4. **Final coherence** — parent default `self` (or one short Review spawn): logic, redundancy, overall sanity vs the two anchors and the original ask.

If any stage is blocked, **stop** dependent stages and follow the sticky-route evidence and parent wait rules — do not skip ahead.

## Pick a backend

Never spawn the **parent’s own family** unless the user named it this turn (Grok parent → no `grok`; Claude Code parent → no `claude`; Codex parent → no `codex`; Antigravity parent → no `agy`). One harness per question unless the user asked for multiple opinions.

Family is the **parent product/CLI**, not the model id. Cursor Agent, `cursor-agent`, and Grok Bot are `cursor` (even when the model is Grok). Grok **Build** CLI is `grok`. Claude Code is `claude`. Codex CLI is `codex`. Antigravity CLI is `agy`. Legacy Gemini CLI is `gemini` (a different family; do not treat it as `agy`). A Cursor parent with `defaults.implement = "cursor"` skips and asks once — that token is a backend, not `self`. Pin `self` when this session should do the job.

| User says | Binary (PATH) | Skill policy default | Default thinking | Flags |
|---|---|---|---|---|
| Claude, Opus, Fable, ask-claude | `claude` | `opus` | `xhigh` | [references/backend-claude.md](references/backend-claude.md) |
| GPT, Codex, Sol, Terra, Luna, Astra, ask-gpt | `codex` | `gpt-5.6-sol` | `xhigh` | [references/backend-codex.md](references/backend-codex.md) |
| Grok, ask-grok | `grok` | `grok-4.6` | `xhigh` | [references/backend-grok.md](references/backend-grok.md) |
| Gemini, Antigravity, agy, ask-gemini | `agy` | vendor default (omit `--model`; list: `agy models`) | `high` | [references/backend-agy.md](references/backend-agy.md) |
| Unspecified | Matching `defaults.*` key in user config (`spec`, `spec-ui`, `plan`, `plan-ui`, `implement`, `implement-ui`, `writer`, `research`, `code-review`, `code-review-visual`, …) if set **and** (backend not the parent family, or value is self-class); else ask once. Review aliases: `code-review-task` / `code-review-adversarial` / `code-review-adverserial` / `review` → `code-review` (see resolution order in user-config). | Config `[models]` / `[effort]`, else table defaults | — | [references/user-config.md](references/user-config.md) |

**Series pin:** A named series is a **model pin**, not only a backend pick. Tokens: `Opus`→`opus`, `Fable`→`fable` (Fable 5.1 on Claude Code ≥2.1.255; older CLIs still resolve `fable` to Fable 5 — pin `claude-fable-5-1` to fail loud), `Sonnet`→`sonnet`, `Haiku`→`haiku`, `Sol`→`gpt-5.6-sol`, `Terra`→`gpt-5.6-terra`, `Luna`→`gpt-5.6-luna`, `Astra`→`gpt-6-astra`. Generic `Claude` / `ask-claude` / `GPT` / `Codex` / `ask-gpt` use config `[models]` else the policy default. Do not use Claude’s `best` alias (silent Fable upgrade). Do not swap the policy default to a vendor’s newest bundled model unless this utterance (or the user config) pins it.

If the user pins a model id, use it. Cursor Agent / OpenCode / Droid / legacy Gemini CLI: [references/more-clis.md](references/more-clis.md) (not in `scripts/spawn.sh`). Config token `gemini` is that legacy CLI, not an alias for `agy`.

**List what this machine actually has:**

```bash
claude --help
codex debug models --bundled
grok models
agy models
cursor-agent --list-models
```

Windows PowerShell: `Get-Command claude,codex,grok,agy`. Do **not** hardcode `~/.local/bin/…`. **`agent` on PATH is often Grok Build, not Cursor.** Cursor’s CLI is `cursor-agent`.

There is no `harness-spawn` skill. Stale `ask-claude` / `ask-gpt` / `ask-grok` stubs: this skill.

## User config

Optional. Survives skill updates. **Never** store prefs in the skill clone (`npx skills add` fans out into every agent dir).

- If `$HARNESS_SUBAGENT_CONFIG` is set: that file. Missing file → ask once (do not fall through).
- Else: `${XDG_CONFIG_HOME:-$HOME/.config}/harness-subagent/config.toml`

Schema, search, and “always use X” write path: [references/user-config.md](references/user-config.md). Do not create the file unless the user asked to pin.

If the matched `defaults.*` value is `self`, `orchestrator`, `parent`, or `you`, do the job in this session. Do not write a brief. Do not call `scripts/spawn.sh`. A parent-family backend (`grok` while you are Grok) is **not** self — skip and ask once unless this utterance names that harness.

## OS, temp, stdin

Parent agents often pipe stdin. Treat that as hostile.

| | Linux / macOS / WSL | Windows cmd | Windows PowerShell |
|---|---|---|---|
| Run dir | `${TMPDIR:-/tmp}/harness-subagent/<run-id>` | `%TEMP%\harness-subagent\<id>` | `Join-Path $env:TEMP "harness-subagent\<id>"` |
| Spawn | `bash <skill>/scripts/spawn.sh …` | Git Bash on the script path | Git Bash **file argv** (below) — never a double-quoted `-lc` recipe |

Invoke `scripts/spawn.sh` from the skill directory of the **SKILL.md you loaded this turn** (path on the skill header). `npx skills add -g` fans out copies; do not mix `~/.claude/skills`, `~/.cursor/skills`, and `~/.agents/skills` in one session.

`cwd` / `-C` / `--cwd` must be a path **that CLI understands** (WSL `/mnt/d/…` vs Windows `D:\…`). Do not mix Windows `claude.exe` into WSL.

Visual screenshots: Claude and Cursor Agent need `--add-dir "$RUN"` with shots in `$RUN`. agy Review/Visual too; agy Implement must **not** pass `--add-dir` (it makes `$RUN` a writable workspace). **Grok: copy shots into `--project` (application tree), never only into `$RUN`** — Grok cannot read the temp run dir. Codex: `-i` (script `--image`).

### Windows PowerShell (gotchas — do not skip)

PowerShell expands `$(…)`, `cat`, and `$RUN` **before** bash sees them. A double-quoted `& bash -lc "claude … $(cat $RUN/brief.md) > $RUN/last.md"` will look for `D:\c\Users\…`, write `last.md` to `/`, or pass an empty/flattened prompt. `system32\bash.exe` is WSL — it cannot see `%TEMP%` as `/c/…`.

1. Pin Git Bash: `"$env:ProgramFiles\Git\bin\bash.exe"` (confirm `Test-Path`; do not use WSL bash).
2. Write `brief.md` with the Write tool (UTF-8). Do **not** `Out-File` / `>` from PowerShell 5.1 (UTF-16LE + NULs).
3. Run the skill script **as arguments**, background the Shell call (`block_until_ms: 0` in Cursor):

```powershell
& "$env:ProgramFiles\Git\bin\bash.exe" -- "<skill-dir>\scripts\spawn.sh" --backend claude --mode review --project "D:/Code/app" --run "C:/Users/<you>/AppData/Local/Temp/harness-subagent/<id>"
```

4. List the run dir with Shell (`Get-ChildItem` / `ls`). Cursor **Glob is workspace-scoped** and will miss `%TEMP%`.
5. Two failed launches → stop. Answer from parent evidence. Mark the harness UNVERIFIED. Do not invent a third quoting recipe.

If this parent auto-allows only some CLIs, the spawn will block on `bash` / `bash.exe`, this script, or the target backend (`codex`, …). Ask the user to allow those, or use an approval mode that can allow the one spawn. Do not hardcode a machine allowlist.

Spawn pins Auto-equivalent permission: Claude/Grok `--permission-mode auto`. Codex all modes `--approve-for-me` (do not also pass `--sandbox`: 0.147 mutex). agy Implement `--dangerously-skip-permissions` (agy has no classifier Auto; this is YOLO). agy Review omits it. Claude Review still omits Edit/Write in `--tools` (Bash remains for temp files). Do not pass `--ask-for-approval` to `codex exec` (TUI-only; exec rejects it). App-edit restraint is the brief (`Do not edit application files.`), not a read-only sandbox.

## Shared protocol

0. **Gate.** Name the one thing you cannot answer from this repo / this context. If you cannot name it, do not spawn — **unless this utterance already named a harness** (utterance still wins; `writer=self` does not suppress “Ask Claude to rewrite the README”). Naming, style, formatting, and “already tried” that already is the answer are not worth a run. **Sustained writer/research** (a README rewrite, a competitive lookup) is not “naming”: spawn when the **resolved route** is a CLI.
1. Write `brief.md` under the temp run dir (never inside the repo).
2. Spawn **`scripts/spawn.sh` in the background** (minutes; a foreground timeout kills spend). Do not copy or edit the script.
3. Wait until the **process exits**. Read its exit status, `$RUN/last.md`, and `$RUN/capture-status.txt` together. Done means the process exited and capture artifacts exist; success additionally requires the CLI status and report verdict to support success. `ok` / `ok-report` describe capture only. A valid report with a nonzero exit requires parent review, never an automatic pass. Process still running + no `VERDICT` yet → not done. `spawn.sh` prefers `$RUN/report.md` over final stdout and normalizes bold/`VERDICT:` lines. Returned nonzero exits still finalize. If selected text has no verdict, stdout and stderr are scanned before empty-output handling. Valid selected verdicts retain precedence. Generic non-limit errors remain `no-verdict` failures. For `usage-limit`, read the labeled evidence and follow the sticky-route parent actions above. For `no-verdict`, mark UNVERIFIED / blocked; do not invent success. Exception: a same-family / “which harness” ask is a **nesting leak** — rewrite the identity fence and relaunch **once** (same backend). Do not relaunch a finished job because of a preamble.
4. Synthesize — never paste-only.

### Persistence, parent wait, and exact resume

`report.md` is the durable checkpoint and must be written before cleanup. Session history adds conversation context; it does not replace the report, prove success, or guarantee exactly-once tool effects. `spawn.sh` checks Python 3 (`python` or `python3`, no jq) for metadata and provider JSONL. Claude/Grok preassign a lowercase UUID and write `session-id` plus `session.json` before launch. Codex saves the first `thread.started.thread_id`; agy saves `init.conversation_id`, including when the CLI exits before a final response. Raw JSONL goes to `events.jsonl`, decoded provider errors to the labeled `provider-errors.log`, and human text to `stdout.md`/`last.md`. Parser errors finalize BLOCKED captures and exit nonzero; they do not replace a `usage-limit` classification. Dry-run publishes no provider identity.

The identity records must agree on backend, exact native ID, resolved original `--project` cwd, model/effort pins, and role. `session.json` records `native_key`, `id`, the native key (`session_id`, `thread_id`, or `conversation_id`), `origin_run`, `attempt_run`, and `preassigned`. A preassigned ID records intent, not proof of persistence. Missing/empty IDs, disagreement, or `persistence_available: false` mean resume unavailable. Claude's `CLAUDE_CODE_SKIP_PROMPT_HISTORY` being set makes persistence unavailable; do not silently override it.

Before yielding for reset/backoff, durably record original run/report paths, backend, exact ID or explicit unavailability, resolved cwd, model/effort and role pins, blocked reason and raw evidence, known reset/retry time with timezone (or unknown), and next action. The parent owns this wait record and the wait; spawn never sleeps, retry-loops, launches a sleeper, or swaps routes.

After the reset/backoff or human credits decision, confirm the previous process exited. Allow at most one active attempt per job. Create a separate attempt directory and copy only the prior `session-id` and `session.json` identity records there. Preserve the prior artifacts. Do not copy the old `report.md` into the new attempt's report slot. Write the short continuation into the new attempt's **`brief.md`** (the executable handoff uses this filename; no extra prompt flag). It must tell the worker to continue unfinished work, read the prior durable report at its explicit path, reconcile it with actual work before repeating effects, retain scope/role/tool restrictions and the worker/no-spawn fence, and write a complete updated report to this attempt before cleanup. Do not replay the full original brief.

```bash
bash scripts/spawn.sh --backend "$BACKEND" --mode "$MODE" \
  --project "$ORIGINAL_PROJECT" --run "$ATTEMPT" \
  --model "$PINNED_MODEL" --effort "$PINNED_EFFORT" \
  --resume-id "$SID"
```

For an unpinned agy model, omit `--model` on both attempts; otherwise re-pass the original model/effort pins. Spawn requires a full lowercase canonical UUID and both copied records; mismatched backend/cwd/pins, junk in `session-id`, missing records, or unavailable persistence produces BLOCKED evidence and a nonzero exit without launching the provider. Exact resume rejection remains BLOCKED; there is no silent fresh-thread fallback. Codex/agy observed identity must match the requested ID, including an empty Codex event stream; agy also blocks a reported `num_turns == 1`. Never use `--continue`, `--last`, bare `--resume`, session-selection `-c`, or `--fork-session`. Codex `-c model_reasoning_effort=…` is configuration and stays. A fresh run from the checkpoint is a separate explicit recovery decision, never represented as successful resume. A repeated limit returns another BLOCKED capture to the parent.

### Write the brief

Task description, not a data dump. **Do not paste diffs or file contents** — name paths and a **bounded** investigation. Exception: files unreachable from the working directory (screenshots under the temp run dir).

- Prefer named files/symbols over “explore the repo.”
- Diff: exact range, `git diff <A>..<B> -- <paths…>`.
- Visual/confirm: **forbid** `git log`, full-tree `git diff`, status dumps. `spawn.sh --image` is Codex only. Claude: copy shots into `$RUN` (already gets `--add-dir "$RUN"`). **Grok: copy shots into `--project`.** Name the files in the brief.
- Put parent evidence under **What was already tried**. Prefer “verify this” over “rediscover.” If you already ran `gh`/`curl` and Codex Review may lack network, put the output here and forbid re-running those commands.
- **Product override:** if the user locked a product decision, say so.

Six parts, in order:

1. **Child identity fence** — paste first, verbatim, from [references/roles.md](references/roles.md). Never write `scripts/spawn.sh` or `--mode visual` in the brief (L2 treats that as an order to re-orchestrate).
2. **Objective** — one sentence naming the verdict / deliverable (role card objective cue).
3. **Where to look** — paths, bounded commands, symbols; edit allowlist if Implement.
4. **What was already tried**
5. **What would change my mind** — settling evidence (Review) or acceptance gates (Implement).
6. **Return format** — paste from [references/roles.md](references/roles.md): the role’s **return contract** (includes **write `report.md` before cleanup**), Superpowers map (exact names), must/must-not, and for implement/implement-ui the **full TDD policy table** (never “see roles.md” alone). Role card wins over any older stub wording. Name the run-dir path for `report.md` when the child cannot infer it. Mode mapping lives in [user-config.md](references/user-config.md), not in the brief.

### Postures → role cards

Index only — full cards + contracts in [references/roles.md](references/roles.md).

| Posture / key | Write? | Card |
|---|---|---|
| **code-review** (aliases: task, adversarial, adverserial, review) | no | Adversarial cleanliness + correctness |
| **code-review-visual** | no | Change review + holistic user-walk |
| **research** | no | Official/modern sources (ANSWER contract) |
| **implement** / **implement-ui** | **yes** | Ship + pasted TDD table |
| **spec** / **plan** / **writer** | **yes** | Light cards + own contracts |
| **Unstuck** | usually no | Independent diagnosis |

Config keys and spawn `--mode`: [references/user-config.md](references/user-config.md). Extra `[defaults]` keys are labels, not inferred. The skill has no author job→harness map.

### Report back — synthesis, never a paste

CTO voice: bullets; ASCII when useful; keep the human aligned.

1. **What was asked** — one line.
2. **Harness verdict** — verbatim first `VERDICT` line (strip preamble).
3. **Where I agree and disagree** — grounded in this codebase.
4. **My recommendation.**

Cheap-check claims (`file:line` exists; tests actually fail). For Implement: files changed **under `--project`**, not only listed in `last.md`. If `--project` is empty and `$RUN` has the app next to `brief.md`, agy treated `--add-dir` as the workspace (spawn.sh must omit `--add-dir` on Implement). If the child listed a gate as NOT RUN / permission declined / sandbox-blocked, the parent runs that gate or leaves it UNVERIFIED. That is not a pass.

### Hang / progress hygiene

- Capture stderr to `$RUN/stderr.log` (the script does this). Codex transcripts are large — normal, not a hang.
- **Done** = `spawn.sh` has exited and capture artifacts exist. **Success** also requires its exit status and verdict to support success. Do not treat a missed `AwaitShell` regex (`exit_code`) as done or as a hang — Cursor terminal footers often do not match that pattern.
- After background spawn: one smoke check (`ls` / `Get-ChildItem` on `$RUN`). After **agy Implement** also list `--project` (the app must land there, not in `$RUN`). Optional notify on stderr `session id:` / `OpenAI Codex` means **started**, not done.
- One wait sized to expected runtime (Codex review often 5–15 min). Do not poll `last.md` every couple of minutes. Do not start a second `spawn.sh` for the same `--run` while the first process is still alive. Process still running + empty `last.md` → not done.
- **Do not kill** because stderr is noisy or mentions `git`. Kill only if the process is dead **and** the report file is empty/stale, or there is no growth and no process activity for a long stretch.
- If a Visual run starts unbounded git: kill, rewrite the brief with the forbid line, relaunch **once**.
- If `last.md` is a same-family / “which harness should I spawn” ask (`no-verdict`, no `VERDICT`): **nesting leak** (L2 ran this skill). Rewrite the brief with the identity fence, relaunch **once**, **same** backend. Do not retarget (sticky). Do not invent a verdict.
- Native Windows: Git Bash file argv. WSL `bash.exe` cannot see `%TEMP%` as `/c/…`. Do not mix them.

### Red flags

| Thought | Reality |
|---|---|
| "It found a bug, I'll just fix it" | Verify first. False positives are the main failure mode. |
| "I'll paste the response" | Synthesis is the deliverable. |
| "It disagrees, so I was wrong" | Decorrelated ≠ correct. |
| "I'll paste the diff to save it a step" | Named paths + bounded range. |
| "Harness must be read-only" | Review must not edit application files; temp/report writes are allowed. Implement may edit when the brief says so. |
| "This task wants Codex / Opus / Grok" | Utterance, then config, then ask. No task map. |
| "Astra/Fable is now latest — change the skill default" | Policy default stays until the user pins it. Series name this turn is a model pin only. |
| "Child hit a usage limit — switch models" | Sticky route. Read labeled limit evidence; parent waits for reset/backoff or asks about spend/ambiguous quota. Stop dependent stages. |
| "Orchestrate this — second opinion" means full loop | Single-job narrowing → one-shot review. |
| "Full loop using Codex" is one-shot because Codex is named | Explicit full-loop language wins; harness only pins backends. |
| "Practices failed limits — continue to Implement" | Stop dependent stages. Apply the parent wait rules to the preserved evidence. |
| "last.md is cleanup chatter but exit 0 — treat as success" | Check capture-status / VERDICT. no-verdict = UNVERIFIED. |
| "Claude finished — stdout is the report" | Prefer report.md; final -p text is last turn only. |
| "Three harnesses is more independent" | One, different family, unless asked for multiple. |
| "I'll nest the bash recipe in PowerShell -lc" | `scripts/spawn.sh` as file argv. |
| "Claude got an empty prompt — feed stdin from the parent" | Empty argv is quoting. Use the script (it already files stdin). |
| "I'll Glob the temp run dir" | Workspace-scoped. Shell `ls`. |
| "Config says Codex and I am Codex" | Skip same family; ask once if nothing else remains. |
| "Config says grok and I am Grok, so I'll just do it" | Same-family still asks once. Pin `self` when the orchestrator should do that job. |
| "AwaitShell missed exit_code — kill or relaunch" | Wait for the process; then read `$RUN/last.md`. |
| "Spawn failed — try another quoting trick" | Two failures then stop. |
| "Config says cursor and I am Cursor Agent" | Same-family skip. Pin `self` when the orchestrator should do that job. |
| "I'll poll last.md until it appears" | One wait sized to runtime. Process + empty last.md = not done. |
| "I'll paste spawn.sh --mode visual into the brief so the child knows the mode" | L1-only argv. Child treats that as an order to spawn. Fence goes in the brief; spawn.sh flags never do. |
| "Child asked which harness — same-family rule working" | L2 leak. Fence, relaunch once, same backend. Do not retarget. |
| "Config says Codex and the child is Codex, so it should ask" | Child already is the worker. Ignore config. Do the job. |
| "I'll call spawn.sh from a different clone than this SKILL.md" | Wrong tree. Use the loaded skill dir. |
| "agy last.md says done, the app shipped" | List `--project`. If empty, the files are in `$RUN` (`--add-dir` on Implement). That is not a pass. |
