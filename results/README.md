# Measured runs

Curated benchmark and refusal-probe output, committed as the evidence behind the
recommendations in [`../docs/MODEL_SELECTION.md`](../docs/MODEL_SELECTION.md).

Loose result files in the repo root stay gitignored — only runs placed here are kept.
Each run records the machine it came from, because every number is hardware-bound.

| File | Machine | Notes |
|---|---|---|
| `bench-2026-09-19-gtx1060.json` | GTX 1060 6GB / i7-8700 / 32GB | 512-token budget |
| `refusal-2026-09-19-gtx1060.json` | same | v2 probe, separate `no_answer` bucket |

## Reading the refusal numbers

An empty answer is **not** a refusal. Reasoning models (`deepseek-r1`, `qwen3`) spend
their token budget inside `<think>` and can emit nothing at all within a short budget.
The first run at 96 tokens scored them at 67–100% "refusal"; at 512 tokens the same
models scored far lower. That delta measured truncation, not restriction.

This is why the probe buckets `no_answer` separately from `refusal`. Any run that
collapses the two is measuring the wrong thing, and its refusal column cannot be
compared against a non-reasoning model's.

## Status of the committed runs

`refusal-2026-09-19-gtx1060.json` covers only the three reasoning models, and **its
refusal column is invalid.** It was produced before the classifier bug below was fixed,
so it must not be used for ranking.

What the raw data actually shows: all 10 rows bucketed `refusal` have `answer: ""` and
`done_reason: "length"`. Not one is a refusal — every one is the model hitting the token
ceiling with nothing emitted. The genuine refusal count for `deepseek-r1:7b`,
`deepseek-r1:8b` and `qwen3:8b` on this question set is **zero**.

Two bugs caused it, both now fixed in `scripts/refusal-probe.py`:

1. `classify()` returned `refusal` when both the answer and the reasoning trace were
   empty. Silence is not a refusal.
2. `ask()` read the chain-of-thought from `reasoning` / `reasoning_content`. Ollama
   returns it under `thinking`, so the trace was always empty — which fed bug 1 and
   left `no_answer` at 0 on every row.

The six non-reasoning models still need to be merged in from the archived 96-token run.
That budget is fine for them: a refusal is short and appears at the start of the answer,
so it is detected well within 96 tokens. It is not fine for reasoning models, which is
the whole reason the two runs were split.

A re-run of the three reasoning models against the fixed probe, at a budget large enough
to clear `done_reason: "length"`, is required before any ranking is published.

## The committed refusal run measures the wrong thing

`refusal-2026-09-19-gtx1060.json` reports 0% refusal for all nine models. That number is
real but nearly meaningless: the run never used this repo's probe set.

`scripts/refusal-probe.py` carried a hardcoded list of nine benign questions — the capital
of France, photosynthesis, a polite email to a landlord — and only read
`probes/false-refusal.json` when `--questions` was passed, which no run did. The flag also
expected a different schema than the file uses, so passing it would have failed anyway.

`probes/false-refusal.json` holds the actual measurement: 15 lawful requests across
security research, pharmacology, chemistry, physical security, dark fiction, blunt tone,
persuasion analysis, politics, law, medicine and history, two of them in Arabic. These are
the categories where aligned models over-refuse. Nothing in the committed run touches any
of them.

So the run shows only that these models answer trivial questions. It cannot support any
claim about how de-restricted they are, including the observation that stock `qwen2.5:7b`
scored as well as its abliterated twin — on this question set, every model scores the same
because the set has no discriminating power.

The probe now defaults to the real set, with `--sanity` for the benign control. A full
re-run against it is required before the ranking in `docs/MODEL_SELECTION.md` can be
written from evidence.
