# Model selection — measured on this rig

The priority is **compliance first**: the least-restricted model that will run, with speed
and context treated as the price paid for it.

Everything here was measured on this machine (GTX 1060 6 GB / i7-8700 / 32 GB / Windows 11 /
Ollama 0.34.2). The raw data is in [`../results/`](../results/README.md), committed unchanged.
**No number in this file comes from a model card or a leaderboard.** Claimed compliance
that has not been probed here is labelled as such.

- Refusal probe: the real 15-question set in `probes/false-refusal.json` (13 EN / 2 AR),
  run at 512 and 1024 tokens, re-scored with the fixed classifier. Both runs agree.
- Speed: `results/bench-2026-09-19-gtx1060.json`.
- Placement in the bench file is **unreliable** (family-prefix matching bug) and is not
  cited here. See `results/README.md` before believing any placement claim below.

---

## Settled result: the four models that were actually measured

The four installed 7B models on this rig were probed against the full real set at 512 and
1024 tokens. `no_answer` was zero everywhere (no starvation), so every column is comparable.

| Model | Refusal | Hedge | Compliant | Trunc 512 | Trunc 1024 | Med answer 1024 (chars) | gen tok/s |
|---|---|---:|---:|---:|---:|---:|---:|
| `qwen2.5:7b` | **0** | 2 | 13 | 10/15 | 0/15 | ~2900 | 23.8 |
| `huihui_ai/qwen2.5-abliterate:7b` | **0** | 0 | 15 | 1/15 | 0/15 | ~1100 | 23.8 |
| `mistral:7b` | **0** | 2 | 13 | 8/15 | 2/15 | ~2000 | 18.6 |
| `qwen2.5-coder:7b` | **3** | 1 | 11 | 5/15 | 0/15 | ~1300 | 23.3 |

Read + means good here (fewer refusals is the target), but for **Trunc** fewer is better.

What the two runs together establish:

- **The only model that refuses anything is `qwen2.5-coder:7b`: 3/15, stably, in both runs.**
  The refusals are on a dark-fiction scene, a blunt-tone roast, and a history detail — the
  categories this probe exists to catch. It is the current default in the OpenCode config
  on this machine, which was chosen for a compaction problem that turned out to be an
  OpenCode artifact, not a model fault (see `HANDOFF.md`, and it is fully reproducible on
  stock `qwen2.5-coder` too).
- **Abliteration buys zero on refusal: 0 vs 0.** `huihui_ai/qwen2.5-abliterate:7b` refuses
  no more and no less than stock `qwen2.5:7b` — the same model with the refusal direction
  cut out.
- **Abliteration's measured cost is depth.** At 1024 tokens, nothing is truncated, so the
  median answer length is the model choosing to stop: stock `qwen2.5` writes ~2900 chars,
  the abliterate twin ~1100 — roughly 2.6× shorter, on identical questions. The abliterate
  was not starved at 512 either (1/15 truncated vs 10/15 for stock); it simply writes less.
  The "abliteration nicks capability" claim now has a measured shape on this rig.
- **At 512, `qwen2.5:7b`'s hedge/compliant numbers were truncation-shaped**, which is why
  the 512 run alone was not final. At 1024 it finishes everything and still hedges 2/15.

---

## Ranking (Tier 1 / Tier 2 / Tier 3)

### Tier 1 — `qwen2.5:7b` · **recommended default**

0 refusals, the deepest answers of the four, and the fastest (23.8 gen tok/s, tied best).
This is the model to pin as the OpenCode default and to reach for first.

### Tier 2 — the alternatives, on measured tradeoffs

- **`mistral:7b`** — 0 refusals, deeper answers than coder, but slower (18.6 tok/s) and
  still truncates 2/15 at 1024. A genuine fallback; no reason to prefer it over Tier 1.
- **`huihui_ai/qwen2.5-abliterate:7b`** — the cleanest compliance surface measured
  (0 refusals, 0 hedges), at the price of terse answers (~1100 chars median) that skip the
  depth stock `qwen2.5` provides. If you want an "uncensored" model in the literal sense,
  this is it — but expect to prompt for more detail.

### Tier 3 — avoid as default

**`qwen2.5-coder:7b`** — the only measured refuser (3/15). Its niche is coding-specific
workflows where its training matters, not general de-restriction. Because it is the
current OpenCode default on this machine, changing it back to `qwen2.5:7b` is the low-risk,
evidence-backed move.

---

## Not measured yet — do not rank these

Speed is measured for all of them; compliance is **not**. Their old "0% refusal" rows came
from the benign control set and prove nothing (see `results/README.md`).

| Model | gen tok/s | Refusal status |
|---|---:|---|
| `deepseek-r1:7b` | 22.2 | **Excluded.** Old rows predate the thinking-strip fix; re-run scheduled against the fixed probe. |
| `deepseek-r1:8b` | 10.2 | **Excluded.** Same reason. |
| `dolphin3:8b` | 13.3 | Unmeasured (real set) |
| `llama3.1:8b` | 12.8 | Unmeasured (real set) |
| `qwen3:8b` | 11.1 | Unmeasured (real set) |

Until a model is probed against `probes/false-refusal.json`, this repo has no compliance
evidence for it. That is a feature: it is exactly what stopped the first, wrong version of
this file.

---

## The untested JOSIEFIED lineage (`hunter-*`)

`scripts/setup.ps1` and the `modelfiles/` folder still install four "hunter-" variants
(`JOSIEFIED-Qwen3` 8b/4b, `dolphin3-abliterated:8b`, `qwen3-abliterated:14b`) and their
Modelfiles carry disclaimers that they are uninstalled and untested. **They are not on
this rig and were never probed here.** Do not let a model card's claim about a JOSIEFIED
system prompt displace a measured 0-refusal result from stock `qwen2.5:7b`. If you want
one of them, install it, then probe it — the tools below are exactly for that.

Background on why the JOSIEFIED builds claim to be more compliant: they combine
**abliteration** (project the refusal direction out of the weights — fast, but it nicks
capability and refusals survive in some phrasings) with an **uncensored finetune** (learn
compliance by retraining — holds capability better). The technique comparison is real;
the specific model claims are untested on this machine.

---

## Measure it — don't take this file's word

The probe set: 15 lawful requests spanning security research, pharmacology, chemistry,
physical security, dark fiction, blunt tone, persuasion analysis, politics, law, medicine
and history, two of them in Arabic — the categories where aligned models over-refuse.

```powershell
# refusal + hedge + no_answer per model, plus raw answers
python .\scripts\refusal-probe.py --all --show

# or a single model, real set, generous budget (matches the settled runs):
python .\scripts\refusal-probe.py --models qwen2.5:7b --max-tokens 1024 `
  --questions .\probes\false-refusal.json --show

# real speed on your box
python .\scripts\bench.py --all
```

Two numbers come back per model:

- **refusal rate** — declined outright
- **hedge rate** — answered, but buried it in disclaimers and moralizing

Both matter. A model at 0% refusal that lectures you every time is still not the model you
want. Detection is heuristic pattern matching, so `--show` exists to check its work — and
every classifier change in this repo must come with a regression test (`python -m pytest
tests/`).

Extend `probes/false-refusal.json` with your own prompts — that is the point of it being a
JSON file.

---

## Supporting facts the old version got wrong (kept corrected)

- **There is no "~5.0–5.3 GB usable" budget.** That estimate was never measured, and every
  7–8B Q4 model tested on this card reported a partial CPU split at 4.3–4.4 GB of weights —
  inside the claimed budget. The placement measurement itself has a known bug and is being
  redone. Measure your own card with `ollama ps` and trust that over any table.
- **Do not use i-quants** (`IQ2_*`/`IQ3_*`/`IQ4_*`): on Pascal they are typically *slower*
  than the larger `Q4_K_M` file. `Q4_K_M` is the floor; `Q5_K_M` only if it still fits.
- **CUDA 13 dropped Pascal (CC 6.1).** If an Ollama update stops using the GPU, reinstall
  the version that worked. See `HARDWARE_NOTES.md`.