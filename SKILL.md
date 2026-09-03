---
name: harness-subagent
description: >
  Use when the user asks to orchestrate, outsource, delegate, or hand off a
  slice to another coding-agent CLI as a one-shot subagent — Claude Code,
  Codex, Grok Build, Cursor Agent, Antigravity CLI, Gemini CLI, OpenCode, or Droid — or to ask
  Claude, ask GPT, ask Codex, ask Grok, ask Gemini, get a second opinion, or pressure-test
  a plan or diff from a different harness. Do not use to install those CLIs or
  to explain their flags.
license: MIT
compatibility: Requires another coding-agent CLI on PATH (claude, codex, grok, agy, and/or cursor-agent). Windows, WSL, Linux, macOS. Git Bash on native Windows.
metadata:
  author: ptmrio
  version: "0.2.2"
---

# Harness Subagent

Dispatch **another coding-agent harness** as a one-shot subagent, then synthesize.

**Core principle: the harness is a subagent, not an oracle.** A model reviewing its own work reproduces its own blind spots. That worth is destroyed if you forward the answer without judging it.

**Orchestrator voice:** CTO-level — brief, concise, bullets, ASCII previews when they beat prose. Stay aligned with the human operator (surface assumptions; ask on irreversible actions and unsettled product preferences; do not silently invent scope).

**Sticky route:** If the child hits usage/rate limits (or any soft failure that tempts a swap), do **not** retarget another backend or model. Report the failure, mark UNVERIFIED / blocked, ask once. In a **full orchestrate loop**, stop the checklist — do **not** continue to later stages without the failed stage’s deliverable (e.g. no Implement if Practices died on a limit).

Do **not** pick a harness because of a task stereotype unless the **user config** has that key (see [references/user-config.md](references/user-config.md)). Routing order: **this utterance → user config → ask once.** Same protocol for every backend. Role personality and Superpowers maps: [references/roles.md](references/roles.md) (**canonical**).

Default to **Review** (do not edit application files). Allow application writes only when the user (or an approved plan) asks for Implement. Review and Visual may create temp files and write reports.

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

If any stage is blocked (including sticky-route limits), **stop** and ask — do not skip ahead.

## Pick a backend

Never spawn the **parent’s own family** unless the user named it this turn (Grok parent → no `grok`; Claude Code parent → no `claude`; Codex parent → no `codex`; Antigravity parent → no `agy`). One harness per question unless the user asked for multiple opinions.

Family is the **parent product/CLI**, not the model id. Cursor Agent, `cursor-agent`, and Grok Bot are `cursor` (even when the model is Grok). Grok **Build** CLI is `grok`. Claude Code is `claude`. Codex CLI is `codex`. Antigravity CLI is `agy`. Legacy Gemini CLI is `gemini` (a different family; do not treat it as `agy`). A Cursor parent with `defaults.implement = "cursor"` skips and asks once — that token is a backend, not `self`. Pin `self` when this session should do the job.

| User says | Binary (PATH) | Default model (latest series) | Default thinking | Flags |
|---|---|---|---|---|
| Claude, Opus, Fable, ask-claude | `claude` | `opus` (also `fable`, `sonnet`, `haiku`) | `xhigh` | [references/backend-claude.md](references/backend-claude.md) |
| GPT, Codex, Sol, Terra, Luna, ask-gpt | `codex` | `gpt-5.6-sol` | `xhigh` | [references/backend-codex.md](references/backend-codex.md) |
| Grok, ask-grok | `grok` | `grok-4.6` | `xhigh` | [references/backend-grok.md](references/backend-grok.md) |
| Gemini, Antigravity, agy, ask-gemini | `agy` | vendor default (omit `--model`; list: `agy models`) | `high` | [references/backend-agy.md](references/backend-agy.md) |
| Unspecified | Matching `defaults.*` key in user config (`spec`, `spec-ui`, `plan`, `plan-ui`, `implement`, `implement-ui`, `writer`, `research`, `code-review`, `code-review-visual`, …) if set **and** (backend not the parent family, or value is self-class); else ask once. Review aliases: `code-review-task` / `code-review-adversarial` / `code-review-adverserial` / `review` → `code-review` (see resolution order in user-config). | Config `[models]` / `[effort]`, else table defaults | — | [references/user-config.md](references/user-config.md) |

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
3. Wait until the **process exits**. Then read `$RUN/last.md` and `$RUN/capture-status.txt`. Process still running + no `VERDICT` yet → not done. `spawn.sh` already prefers `$RUN/report.md` over final stdout and normalizes bold/`VERDICT:` lines. If status is `usage-limit` or `no-verdict`, mark the harness UNVERIFIED / blocked — do **not** invent a verdict and do **not** retarget backends (sticky route). Do not relaunch a finished job because of a preamble.
4. Synthesize — never paste-only.

### Write the brief

Task description, not a data dump. **Do not paste diffs or file contents** — name paths and a **bounded** investigation. Exception: files unreachable from the working directory (screenshots under the temp run dir).

- Prefer named files/symbols over “explore the repo.”
- Diff: exact range, `git diff <A>..<B> -- <paths…>`.
- Visual/confirm: **forbid** `git log`, full-tree `git diff`, status dumps. `spawn.sh --image` is Codex only. Claude: copy shots into `$RUN` (already gets `--add-dir "$RUN"`). **Grok: copy shots into `--project`.** Name the files in the brief.
- Put parent evidence under **What was already tried**. Prefer “verify this” over “rediscover.” If you already ran `gh`/`curl` and Codex Review may lack network, put the output here and forbid re-running those commands.
- **Product override:** if the user locked a product decision, say so.

Five parts, in order:

1. **Objective** — one sentence naming the verdict / deliverable (role card objective cue).
2. **Where to look** — paths, bounded commands, symbols; edit allowlist if Implement.
3. **What was already tried**
4. **What would change my mind** — settling evidence (Review) or acceptance gates (Implement).
5. **Return format** — paste from [references/roles.md](references/roles.md): the role’s **return contract** (includes **write `report.md` before cleanup**), Superpowers map (exact names), must/must-not, and for implement/implement-ui the **full TDD policy table** (never “see roles.md” alone). Role card wins over any older stub wording. Name the run-dir path for `report.md` when the child cannot infer it.

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
- **Done** = `spawn.sh` has exited **and** `$RUN/last.md` exists. Do not treat a missed `AwaitShell` regex (`exit_code`) as done or as a hang — Cursor terminal footers often do not match that pattern.
- After background spawn: one smoke check (`ls` / `Get-ChildItem` on `$RUN`). After **agy Implement** also list `--project` (the app must land there, not in `$RUN`). Optional notify on stderr `session id:` / `OpenAI Codex` means **started**, not done.
- One wait sized to expected runtime (Codex review often 5–15 min). Do not poll `last.md` every couple of minutes. Do not start a second `spawn.sh` for the same `--run` while the first process is still alive. Process still running + empty `last.md` → not done.
- **Do not kill** because stderr is noisy or mentions `git`. Kill only if the process is dead **and** the report file is empty/stale, or there is no growth and no process activity for a long stretch.
- If a Visual run starts unbounded git: kill, rewrite the brief with the forbid line, relaunch **once**.
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
| "Child hit a usage limit — switch models" | Sticky route. Do not retarget. Report and ask once. Stop later orchestrate stages. |
| "Orchestrate this — second opinion" means full loop | Single-job narrowing → one-shot review. |
| "Full loop using Codex" is one-shot because Codex is named | Explicit full-loop language wins; harness only pins backends. |
| "Practices failed limits — continue to Implement" | Stop the checklist. Ask once. |
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
| "I'll call spawn.sh from a different clone than this SKILL.md" | Wrong tree. Use the loaded skill dir. |
| "agy last.md says done, the app shipped" | List `--project`. If empty, the files are in `$RUN` (`--add-dir` on Implement). That is not a pass. |
