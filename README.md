# Local Uncensored LLM Rig — GTX 1060 6GB / i7-8700 / 32 GB

A reproducible Ollama setup for running **uncensored (abliterated) local models** on a
Pascal-era 6 GB GPU. Nothing here calls a cloud API — every model runs on your own machine.

> **العربية:** [`README.ar.md`](README.ar.md)

---

## Target machine

| Component | Spec | Why it matters |
|---|---|---|
| CPU | Intel Core i7-8700 (6C / 12T, 3.2–4.6 GHz, AVX2) | Handles CPU-offloaded layers. No AVX-512, so CPU-only speed is modest. |
| RAM | 32 GB DDR4 | Large enough to spill a 14B model to system memory. This is your headroom. |
| GPU | NVIDIA GTX 1060 6 GB (Pascal, CC 6.1, 192 GB/s) | **6 GB VRAM is the hard limit.** Bandwidth, not compute, sets tokens/sec. |
| OS | Windows 11 Pro | Ollama native Windows build. |

VRAM is the binding constraint, and less of it is usable than the sticker says: Windows
WDDM, the desktop compositor, the CUDA context and the KV cache all take a cut before a
single weight is loaded. A model that does not fit gets split across GPU and CPU, and
throughput falls off a cliff.

**Do not trust a budget figure from a guide, including an earlier version of this one.**
An estimate here of ~5.0–5.3 GB usable proved optimistic: every 7–8B Q4 model tested on
this card reported a partial CPU split at 4.3–4.4 GB of weights. That measurement has its
own known bug and is being redone — see [`results/README.md`](results/README.md). Measure
your own card with `ollama ps` and trust that over any table.

---

## Quick start

```powershell
# 1. Install Ollama for Windows (once), then:
git clone https://github.com/<you>/ollama-uncensored-lab.git
cd ollama-uncensored-lab

# 2. Check the machine is actually using the GPU
powershell -ExecutionPolicy Bypass -File .\scripts\doctor.ps1

# 3. Pull the recommended model (the measured default)
ollama pull qwen2.5:7b

# 4. Measure real tokens/sec, and real refusal rates, on YOUR box
python .\scripts\bench.py --all
python .\scripts\refusal-probe.py --all --show
```

Then just:

```powershell
ollama run qwen2.5:7b     # measured default: 0 refusals, deepest answers, fastest
```

`scripts/setup.ps1` still installs the untested `hunter-*` JOSIEFIED lineage for
experimenting — none of those models has been probed on this rig, so nothing measured in
this repo backs them. The rankings below are the measured ones, not those.

---

## The models, ranked by what was measured

Compliance is the ranking criterion here, not speed. Speed is the price. Every claim in
this section was measured on this exact machine against the real 15-question probe set
(`probes/false-refusal.json`, 13 EN / 2 AR). Raw runs are archived in
[`results/`](results/README.md). Model-card claims are not evidence here.

### Why some "uncensored" models are more uncensored than others

Two different techniques, and the difference is the single most useful thing to understand:

- **Abliteration** projects the refusal direction out of the weights. Surgery, not
  training. Works, but refusals survive in some phrasings and it nicks capability.
- **Uncensored finetuning** (Dolphin, Lexi) retrains on de-aligned data. Holds up better
  on capability and tends to comply more thoroughly.

The measured result on this rig for the abliterated twin of the default model:
**abliteration bought zero refusals — 0 vs 0 — and cost depth.** See the table below.

### The measured four (settled: two runs agree, 512 + 1024 tokens)

| Model | Refusal | Hedge | Compliant | Med answer (1024t) | gen tok/s |
|---|---|---:|---:|---:|---:|
| **`qwen2.5:7b`** · recommended default | **0** | 2 | 13 | ~2900 chars | 23.8 |
| `huihui_ai/qwen2.5-abliterate:7b` | 0 | 0 | 15 | ~1100 chars | 23.8 |
| `mistral:7b` | 0 | 2 | 13 | ~2000 chars | 18.6 |
| `qwen2.5-coder:7b` | **3** | 1 | 11 | ~1300 chars | 23.3 |

### 1. `qwen2.5:7b` — the default

0 refusals on the real probe set, the deepest answers (median ~2900 chars at 1024 tokens,
the most of the four), tied for fastest. **This is the model to use and the one OpenCode
should be pointed at.**

### 2. `mistral:7b` — fallback, measured

0 refusals, solid depth, but slower (18.6 tok/s) and still truncates 2/15 at 1024. Nothing
wrong with it; nothing above Tier 1 for it.

### 3. `huihui_ai/qwen2.5-abliterate:7b` — the literal "uncensored" option

0 refusals AND 0 hedges — the cleanest compliance surface measured. The cost is real and
measured: its answers are ~2.6× shorter than stock `qwen2.5` on the same questions. It is
not starved (it finished 14/15 even at 512); it simply writes less. Use it if you want the
abliterated experience; expect to prompt for detail.

### 4. `qwen2.5-coder:7b` — the only measured refuser

**Refuses 3/15**, stably across both runs: a dark-fiction scene, a blunt-tone roast, a
history detail. It is the current OpenCode default on this machine, chosen to fix a
compaction problem that turned out to be an OpenCode artifact reproducible on the stock
model too — not a model fault. Nothing in its refusal profile recommends it as the default.

Full reasoning, the unmeasured five (deepseek pair excluded, llama3.1/dolphin3/qwen3
unprobed), and the untested `hunter-*` lineage:
[`docs/MODEL_SELECTION.md`](docs/MODEL_SELECTION.md).

---

## Measure the censorship instead of trusting a ranking

The ordering above is now backed by measurements on this machine against the real
15-question probe set. Your prompts are still not our prompts — extend the set and re-measure:

```powershell
python .\scripts\refusal-probe.py --all          # refusal + hedge rate per model
python .\scripts\refusal-probe.py --all --show   # and read the actual responses
```

`probes/false-refusal.json` holds lawful requests across the categories where aligned
models most often refuse by mistake — security research, pharmacology, chemistry, physical
security, dark fiction, blunt tone, contested politics, law — plus two in Arabic, because
models routinely refuse in Arabic what they answer in English.

You get two numbers per model:

- **refusal rate** — declined outright
- **hedge rate** — answered, but buried it in disclaimers and moralizing

Both matter. A model at 0% refusal that lectures you every time is still not what you
want. The probe set is a JSON file so you can extend it with your own prompts.

---

## Two things that will bite you on a GTX 1060

These are Pascal-specific and most "best local LLM" guides get them wrong.

**1. CUDA 13 dropped Pascal.** CUDA 13.0 removed support for compute capability 5.0–7.2,
which includes your CC 6.1 card. Support for the GTX 1060 lives on the CUDA 12.x line. If
an Ollama upgrade ever ships a CUDA-13-only build, your GPU silently stops being used and
everything falls back to CPU. **Run `doctor.ps1` after every Ollama update** — it fails
loudly if the GPU has dropped out. Pin your working Ollama version before upgrading.

**2. Do not use IQ-quants.** `IQ2_*`, `IQ3_*`, `IQ4_*` trade compute for size. Pascal does
not have the throughput to absorb that trade, and they routinely run *slower* than the
larger `Q4_K_M` file on this generation of card. Pascal's FP16 rate is also crippled
(1/64 of FP32), so K-quants with FP32 accumulation are the right choice. **Q4_K_M is the
sweet spot; Q5_K_M only if the model is small enough to still fit.**

More: [`docs/HARDWARE_NOTES.md`](docs/HARDWARE_NOTES.md) ·
[`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)

---

## Verifying, not trusting

Registry tags move and blog benchmarks are run on other people's hardware. Two commands
settle any disagreement on your own machine:

```powershell
ollama ps                            # is it 100% GPU, or did it spill to CPU?
python .\scripts\bench.py --all      # real tok/s and GPU/CPU split per model
python .\scripts\refusal-probe.py --all  # real refusal and hedge rates per model
```

`bench.py` writes `bench-results.json` so you can compare before and after a settings
change instead of guessing.

---

## Responsible use

Abliterated models have had their refusal behaviour removed. That makes them useful for
research, red-teaming, security work, fiction, and for avoiding the false refusals that
make general-purpose models annoying — and it also means **nothing stops them from
producing harmful output**. There is no safety layer between you and the weights. Keep
these models local, do not put an unfiltered one behind a public endpoint, and stay inside
the law that applies to you.

## License

MIT — see [`LICENSE`](LICENSE). Individual model weights carry their own upstream licenses
(Qwen: Apache-2.0; Llama-derived Dolphin: Llama 3.1 Community License). Check them before
any commercial use.
