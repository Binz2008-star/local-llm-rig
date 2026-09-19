# Handoff

Shared state for every agent and session working on this repo — Claude Code, OpenCode,
or a human. Read it before doing anything; update it before you stop.

**The repo is the source of truth, not any chat log.** If this file and the code
disagree, the code wins and this file is wrong — fix it.

---

## Current state

| | |
|---|---|
| Branch | `main` (no other branches; work directly on it) |
| Remote | `github.com/Binz2008-star/local-llm-rig` (private) |
| Rig | GTX 1060 6GB / i7-8700 / 32GB / Windows 11 / Ollama 0.34.2 |
| Models pulled | 9, listed in `results/bench-2026-09-19-gtx1060.json` |

### Two working copies exist — keep them in sync

| Path | What it is |
|---|---|
| `~/local-llm-rig-repo` | the git clone; **edit here, commit here** |
| `~/local-llm-rig` | flat scratch folder where runs execute |

Scripts are copied from the clone into the flat folder to run. Never edit the flat copy —
changes there are invisible to git and will be silently overwritten. Before any run:

```powershell
Copy-Item "$HOME\local-llm-rig-repo\scripts\refusal-probe.py" "$HOME\local-llm-rig\" -Force
Copy-Item "$HOME\local-llm-rig-repo\probes" "$HOME\local-llm-rig\" -Recurse -Force
```

---

## What is measured and trustworthy

**Throughput** — `results/bench-2026-09-19-gtx1060.json`, all 9 models, 512-token budget.
Valid. Range 10.2–23.8 gen tok/s.

**Placement is NOT trustworthy in that file.** Eight rows report `in_vram: false` and
`deepseek-r1:8b` reports `null` — but `scripts/bench.py` matched the loaded model by family
prefix, so `qwen2.5` could pick up `qwen2.5-coder`'s numbers and `deepseek-r1:7b` could pick
up `:8b`'s. Any placement row may belong to a different model. Fixed to match on the exact
tag; **placement needs re-measuring**, and the throughput numbers are unaffected.

The run also did not record `OLLAMA_KV_CACHE_TYPE`, which is unset on this machine — so it
ran with the f16 default, twice the size of the `q8_0` that `setup.ps1` is meant to
configure. Some of the observed spill is likely that, not the weights. The bench now
records the cache type; a re-measure should set it first.

## The refusal result — settled for the 4 contended models

The four models actually in contention have been probed against the real 15-question set at
both 512 and 1024 tokens, re-scored offline with the classifier at HEAD. The numbers agree
across both budgets, so the refusal column is final for them:

| model | refusal | hedge | compliant | notes |
|---|---|---|---|---|
| qwen2.5:7b | **0** | 2 | 13 | hedges are lawyer/doctor referrals — appropriate |
| huihui_ai/qwen2.5-abliterate:7b | **0** | 0 | 15 | writes the shortest answers of the four |
| qwen2.5-coder:7b | **3** | 1 | 11 | the only model that refuses anything |
| mistral:7b | **0** | 2 | 13 | same appropriate referral hedges |

Evidence: `results/refusal-2026-09-19-gtx1060-4model-1024tok-rescored.json` (and the `-512tok-`
pair). The raw archives are kept unmodified beside them.

Two conclusions the data supports:

- **Abliteration bought nothing on refusal** (0 vs stock's 0) and its answers are ~half the
  length at the same budget (1/15 truncated vs stock's 10/15 at 512 tokens). Token count is
  a proxy, not a capability measure — but the direction is consistent.
- **`qwen2.5-coder` is the only restrictive model of the four (3/15)** — and it is the
  current OpenCode default, switched to for what turned out to be a harness artifact (see
  below). The evidence-backed default is stock `qwen2.5:7b`.

Still **not** done: deepseek-r1 pair not re-run against the fixed probe; the other five
models not probed against the real set; no ranking written.

### The two stale results still in the tree, do not cite

- `results/refusal-2026-09-19-gtx1060.json` — the original 9-model run on the *benign* set.
  0% refusal for all nine, measures only that they name the capital of France.
- Placement (`vram` blocks) in `results/bench-...json` — matched by family prefix, needs
  re-measuring with `OLLAMA_KV_CACHE_TYPE=q8_0` set. Throughput in that file is valid.

### The eight bugs found, each pinned by a regression test now

Each shipped, produced a clean summary table, and was caught only by reading raw JSON.
`tests/test_classify.py` pins every one; CI (`.github/workflows/tests.yml`) runs on push.

1. empty output counted as `refusal` — `2cfc339`
2. chain-of-thought read from the wrong response key — `2cfc339`
3. inline `<think>` blocks classified as answer text — `c0fef02`
4. the real probe set never loaded — `684afd4`
5. probe set didn't resolve from the flat folder; a miss silently used the benign set — `cf5438d`
6. refusal markers matched anywhere, so quoted/narrated refusals scored as refusals — `a21481d`
7. hedge markers included ordinary discourse (`however`, `always`, `consider`) — `a8e9d0c`
8. `THINK_RE` had `\\Z` not `\Z`, so an unclosed `<think>` was never stripped — `99cadda`

Five of these restored safeguards the original probe had and a shorter rewrite dropped.
**When a rewrite comes back shorter, find out what it removed before trusting it.**

### The OpenCode "garbage on hi" finding

Typing `hi` in OpenCode produced a large off-topic template (a conversation summary, or a
repo-audit), not a greeting. This is **not** a model fault and not abliteration: it
reproduced on stock `qwen2.5-coder` too. OpenCode runs a compaction/summary step at session
start and surfaces its output as if it were a reply. The model executed the task it was
handed; the wrong task reached it. A bare `ollama run <model>` answers `hi` normally.

---

## Next actions, in order

1. **Re-run the deepseek-r1 pair** against the fixed probe (`99cadda`+), real set, 1024
   tokens. Pull first — bug 8 (`99cadda`) would corrupt every truncated r1 answer otherwise.
   Commit raw, then re-score offline like the others.
2. **Probe the other five models** (llama3.1, dolphin3, qwen3, deepseek pair) against the
   real set if a full 9-model ranking is wanted. Otherwise the 4-model result stands.
3. ~~Rewrite `docs/MODEL_SELECTION.md`.~~ **Done** — rewritten from the measured four
   (7B result, settled), the unmeasured five listed as unmeasured, placement
   caveat carried over, JOSIEFIED/hunter-* lineage labelled untested. README.md,
   README.ar.md, docs/TROUBLESHOOTING.md, docs/HARDWARE_NOTES.md and results/README.md
   updated to match. The four-installed-7B ranking is final; it no longer suggests a
   model that has not been measured.
4. **Re-measure placement** with `OLLAMA_KV_CACHE_TYPE=q8_0` set, using the exact-tag bench
   (`9f7432f`+). Then the "does anything fit fully on 6 GB" question can be answered.

Done since this list was first written: OpenCode config template (`c645b61`),
`HARDWARE_NOTES.md` correction (`b0fc587`), `hunter-*.Modelfile` labelled untested
(`29e2aa5`), README VRAM-budget retraction (`4ec0ae4`), tests + CI (`99cadda`),
4-model refusal run archived + re-scored (`8240041`, `997d485`), HANDOFF settle-up
(`18996f4`), documentation rewrite (`HEAD of this update`).

---

## Coordination rules

These were learned by getting them wrong in this repo.

**One writer at a time.** Two agents fixed the same probe bug in two copies of the file
in the same hour. Before editing, say what you are taking. After pushing, say what landed
and at which commit.

**Verify against the source of truth, not a convenient substitute.** A branch was reported
deleted after searching the wrong repository. Results were reported pushed while still
untracked. Check the actual remote, the actual `git status`, the actual pushed blob.

**"Placed" is not "committed" is not "pushed."** Only the last one counts.

**Read the raw data, not the summary.** All four probe bugs produced clean, plausible
summary tables. Every one was caught by opening the JSON and looking at individual
answers, `done_reason` values, and answer lengths.

**A smaller rewrite is not automatically a better one.** The probe rewrite came in shorter
and had dropped five safeguards the original had — each one a bug found later.

**Say what a number does not prove.** 0% refusal on benign questions is not evidence of a
de-restricted model. Scope every claim to what was actually tested.

**Every classifier change needs a test.** Eight bugs, all in pure functions, all
preventable by `python -m pytest tests/`. Run it before you push a probe change, and add a
test for anything new you fix.

---

## Conventions

- Results go in `results/` with a dated, hardware-tagged filename. Loose result files in
  the repo root are gitignored on purpose.
- Every result file states the machine it came from. All numbers here are hardware-bound.
- Commit messages explain *why*, and cite the evidence when they correct a previous claim.
- Do not commit third-party content. A README from another repo was published here by
  mistake and had to be removed from history.
