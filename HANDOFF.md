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
Valid. Range 10.2–23.8 gen tok/s. Every model reports `in_vram: false`: even a 4.4 GB Q4
7B partially offloads to system RAM on this card.

## What is measured and NOT trustworthy

**Refusal** — `results/refusal-2026-09-19-gtx1060.json` reports 0% refusal for all nine
models. Do not cite it. The run used a hardcoded set of nine benign questions, not
`probes/false-refusal.json`. It shows only that these models will name the capital of
France. See `results/README.md` for the full account.

Four separate bugs were found and fixed in the probe. Each one invalidated a published
number, and each was found only by reading the raw JSON rather than the summary:

1. empty output counted as `refusal` — fixed in `2cfc339`
2. chain-of-thought read from the wrong response key — fixed in `2cfc339`
3. inline `<think>` blocks classified as answer text — fixed in `c0fef02`
4. the real probe set never loaded — fixed in `684afd4`

**No ranking has been published, and none should be until a real run exists.**

---

## Next actions, in order

1. **Run the real probe set.** Narrow first — the four models actually in contention,
   about 35 minutes:
   ```powershell
   cd "$HOME\local-llm-rig"
   python refusal-probe.py --models qwen2.5:7b,huihui_ai/qwen2.5-abliterate:7b,qwen2.5-coder:7b,mistral:7b --max-tokens 512
   ```
   Expect real `REF` and `HEDGE` hits. Commit the output to `results/` with a dated,
   machine-tagged filename. If the console prints the token-starvation warning, raise
   `--max-tokens` and rerun; the numbers are not comparable otherwise.

2. **Re-run the deepseek-r1 pair** once the above lands. Their old rows were classified
   against reasoning text, before fix 3.

3. **Rewrite `docs/MODEL_SELECTION.md`.** It currently recommends four models that are
   not installed and were never tested (`JOSIEFIED-Qwen3` 8b/4b,
   `huihui_ai/dolphin3-abliterated:8b`, `huihui_ai/qwen3-abliterated:14b`) and ranks them
   on guesses. Replace with the nine measured models. Blocked on step 1.

4. **Correct `docs/HARDWARE_NOTES.md`.** It claims models under ~4.8 GB sit 100% on GPU.
   Measurement says otherwise for all nine. Not blocked — can be done now.

5. **Decide the fate of `modelfiles/hunter-*.Modelfile`.** All four build from base images
   that are not installed. Delete them or mark them clearly as untested proposals.

6. **Commit an `opencode/opencode.jsonc` template.** The live config at
   `~/.config/opencode/opencode.jsonc` is not in version control, so the setup is not
   reproducible.

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

**A smaller rewrite is not automatically a better one.** The probe rewrite came in 184
lines shorter and had dropped three safeguards the original had.

**Say what a number does not prove.** 0% refusal on benign questions is not evidence of a
de-restricted model. Scope every claim to what was actually tested.

---

## Conventions

- Results go in `results/` with a dated, hardware-tagged filename. Loose result files in
  the repo root are gitignored on purpose.
- Every result file states the machine it came from. All numbers here are hardware-bound.
- Commit messages explain *why*, and cite the evidence when they correct a previous claim.
- Do not commit third-party content. A README from another repo was published here by
  mistake and had to be removed from history.
