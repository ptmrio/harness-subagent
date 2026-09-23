# Models

Spoken names resolve to these ids. Prices are USD per million tokens, standard rate, short context, as published on 2026-09-22. A higher effort does not change the per-token rate. It spends more tokens, and those tokens are billed at the output rate.

Pass `--effort` yourself. If you omit it, the CLI uses its own default.

## Claude Code (`claude`)

| Say | Id | Input | Output | Efforts |
|---|---|---:|---:|---|
| Opus 5.5, Opus | `claude-opus-5-5` | 4 | 20 | low, medium, high, xhigh, max |
| Fable 5.1, Fable | `claude-fable-5-1` | 10 | 50 | low, medium, high, xhigh, max |
| Sonnet 5, Sonnet | `claude-sonnet-5` | 2 | 10 | low, medium, high, xhigh, max |
| Haiku 4.5, Haiku | `claude-haiku-4-5-20251001` | 1 | 5 | none |

Opus 5.5 shipped 2026-09-22. The short alias `opus` in Claude Code 2.1.280 points at it on the Anthropic API. This skill passes the full id.

Vendor descriptions, from the Claude Code model docs (accessed 2026-09-22).

| Effort | What Anthropic says |
|---|---|
| low | Short, scoped, latency-sensitive tasks that are not intelligence-sensitive. |
| medium | Less token use. The default on Opus 5.5. |
| high | Balance of tokens and intelligence. The default on Fable 5.1 and Sonnet 5. |
| xhigh | Deeper reasoning, higher token spend. |
| max | May help on hard tasks, with diminishing returns and overthinking. |

Published scores that name an effort, from the Opus 5.5 announcement (2026-09-22).

| Benchmark | Opus 5.5 | Effort on that score |
|---|---:|---|
| FrontierCode v1.1 | 54.6% | medium |
| CursorBench 4.0 | 52.5% | medium |
| FrontierCode v1.1 | 54.4% | max |
| CursorBench 4.0 | 57.8% | max |
| Terminal-Bench 4.0 | 66.4% | xhigh |

Sources: https://platform.claude.com/docs/en/about-claude/pricing and https://www.anthropic.com/news/claude-opus-5-5

## Codex (`codex`)

| Say | Id | Input | Output | Efforts |
|---|---|---:|---:|---|
| Astra | `gpt-6-astra` | 10 | 50 | low, medium, high, xhigh, max, ultra |
| Sol, GPT-6 Sol | `gpt-6-sol` | 2 | 10 | low, medium, high, xhigh, max, ultra |
| Luna, GPT-6 Luna | `gpt-6-luna` | 0.10 | 0.50 | low, medium, high, xhigh, max |
| GPT-5.6 Sol | `gpt-5.6-sol` | 4 | 20 | low, medium, high, xhigh, max, ultra |
| Terra, GPT-5.6 Terra | `gpt-5.6-terra` | 2 | 12 | low, medium, high, xhigh, max, ultra |
| GPT-5.6 Luna | `gpt-5.6-luna` | 0.20 | 1.20 | low, medium, high, xhigh, max |
| GPT-5.5 | `gpt-5.5` | 5 | 30 | low, medium, high, xhigh |
| GPT-5.4 | `gpt-5.4` | 2.50 | 15 | low, medium, high, xhigh |

Saying Sol or Luna selects the GPT-6 ids. GPT-5.6 Sol and GPT-5.6 Luna stay under those versioned names. There is no GPT-6 Terra as of 2026-09-23, so Terra still selects `gpt-5.6-terra`. GPT-5.4 is retired for ChatGPT sign-in as of 2026-08-31. GPT-5.6 Sol's 4/20 price is promotional at least through 2026-11-21. Prices above are standard short-context rates. Ultra is a product mode that runs parallel agents. It is not a separate per-token price. The API pages for GPT-6 Sol and Luna also list `none` and default to medium. This CLI's catalog does not list `none`. It does list `ultra` for Astra and GPT-6 Sol.

| Effort | What OpenAI says |
|---|---|
| low | Efficient reasoning, modest latency. |
| medium | Balance of quality, latency, and cost. |
| high | Hard reasoning and debugging. |
| xhigh | Longer agent work, more time and tokens. |
| max | More time than xhigh for checks and revision. |
| ultra | Parallel agents. Not an API `reasoning.effort` value. |

Published scores. These are not one shared test.

| Model | Benchmark | Score | Effort label |
|---|---|---:|---|
| Astra | Terminal-Bench 4.0 | 57.9% | maximum across efforts, winning effort not named |
| GPT-5.6 Sol | Terminal-Bench 4.0 | 37.3% | maximum across efforts, winning effort not named |
| GPT-5.5 | Terminal-Bench 2.0 | 82.7% | xhigh |
| GPT-5.4 | Terminal-Bench 2.0 | 75.1% | xhigh |

Sources: https://developers.openai.com/api/docs/pricing, https://developers.openai.com/api/docs/models/gpt-6-sol, and https://developers.openai.com/api/docs/models/gpt-6-luna (accessed 2026-09-23). Earlier scores: https://openai.com/index/gpt-6-astra/ and https://openai.com/index/introducing-gpt-5-5/ (accessed 2026-09-22). No GPT-6 Sol or Luna benchmark score is copied here, because those pages did not publish one.

## Grok Build (`grok`)

Prices below are the global endpoint under 200k prompt tokens. At 200k and above, input and output double.

| Say | Id | Input | Output | Efforts |
|---|---|---:|---:|---|
| Grok 4.7 | `grok-4.7` | 2 | 6 | low, medium, high, xhigh |
| Grok 4.7 Fast | `grok-4.7-build-fast` | 4 | 12 | low, medium, high, xhigh |
| Grok 4.6 | `grok-4.6` | 2 | 6 | low, medium, high, xhigh |
| Grok 4.5 | `grok-4.5` | 2 | 6 | low, medium, high |

`grok-4.7-build-fast` is the id `grok models` printed on this class of machine on 2026-09-22. The public docs say "Grok 4.7 Fast" and do not print that slug. `xhigh` is documented for Grok 4.6 and later. The 4.5 card also lists it, and the 2026-09-21 reasoning guide says 4.5 treats `xhigh` as `high`.

| Benchmark | Grok 4.7 | Effort column |
|---|---:|---|
| CursorBench 4.0 | 46.3% | xHigh |
| DeepSWE v1.1 | 71.0% | high (starred cell) |
| Terminal-Bench 4.0 | 37.6% | xHigh |

Source: https://x.ai/news/grok-4-7 (2026-09-21) and https://docs.x.ai/developers/pricing (accessed 2026-09-22).

## Antigravity (`agy`) and Cursor CLI (`cursor`)

No fixed model list lives here. Pass the id the CLI accepts. `agy` efforts are `low`, `medium`, and `high`. Cursor has no separate effort flag. When you pass `--effort`, the spawn command writes it into the model id as `[effort=...]`, which `cursor-agent --help` documents.

List Cursor models with `cursor-agent --list-models`. The binary is `cursor-agent`. On this platform `agent` is often Grok, not Cursor.
