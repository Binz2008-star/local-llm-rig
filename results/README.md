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
