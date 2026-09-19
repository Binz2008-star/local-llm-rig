# Pascal-specific notes (GTX 1060 6GB, CC 6.1)

Generic local-LLM advice is written for Ampere and newer. Several pieces of it are wrong
for a 2016 Pascal card. These are the differences that actually change your results.

## 1. CUDA 13 dropped Pascal — this is a ticking upgrade hazard

CUDA 13.0 removed support for compute capability 5.0 through 7.2 (Maxwell, Pascal, Volta).
Supported architectures now start at Turing (sm_75). The GTX 1060 is CC 6.1, so it is
supported only by the **CUDA 12.x** line.

Ollama currently ships runtimes that still cover older architectures, but the failure mode
if that ever changes is nasty: **no error, no warning — the GPU is simply not used** and
generation falls back to the CPU at roughly a fifth of the speed.

Defend against it:

- Run `scripts/doctor.ps1` after every Ollama update. It exits non-zero if the GPU is gone.
- Note the Ollama version that works (`ollama --version`) before upgrading, so you can
  reinstall it.
- If a future release breaks Pascal, the fallback is llama.cpp built against CUDA 12.x.

## 2. Do not use i-quants (IQ2/IQ3/IQ4)

i-quants achieve smaller files by doing more arithmetic per weight. That trade assumes you
have compute to spare. Pascal does not: the GTX 1060 has 192 GB/s of bandwidth and modest
shader throughput, with no tensor cores at all.

The result is counter-intuitive and consistently reported on this generation: an `IQ4_XS`
file can be *smaller and slower* than the `Q4_K_M` of the same model.

**Use `Q4_K_M`.** Use `Q5_K_M` only when the model is small enough that it still fits with
room for the KV cache. Ignore the i-quant column in comparison tables.

## 3. FP16 is crippled on consumer Pascal

GP106 runs FP16 at 1/64 of its FP32 rate. Anything that leans on half-precision math is a
trap. In practice llama.cpp/Ollama handle this correctly by accumulating in FP32 for
K-quants, which is another reason K-quants are the right family here.

The practical consequence: **flash attention is not a guaranteed win on Pascal.** On modern
cards you enable it and move on; here it can be neutral or slower. Measure it:

```powershell
$env:OLLAMA_FLASH_ATTENTION="1"; # restart ollama, then bench
python .\scripts\bench.py --models qwen2.5:7b
```

Then set it to `"0"`, restart, and bench again. Keep whichever wins.

## 4. KV cache quantization is the lever that actually matters

On a 6 GB card, the KV cache is part of the difference between 100% GPU and a CPU split.
Quantizing it to `q8_0` roughly halves its footprint against the default `f16`, with
quality loss that is hard to notice in practice. That effect has not been measured on this
rig (see section 8).

**Check it is actually set.** On 2026-09-19 `OLLAMA_KV_CACHE_TYPE` was empty in both the
User and Machine environments on this machine, so the bench in section 8 most likely ran
with the default `f16` cache. The bench file does not record the setting; if you re-run,
record it.

```powershell
setx OLLAMA_KV_CACHE_TYPE "q8_0"
```

`setup.ps1` sets this for you. `q4_0` halves it again and is available if you are
desperate for context on Tier 2, but the quality cost there is real.

## 5. Bandwidth, not the CPU, sets your token rate

Once a model is fully resident on the GPU, generation speed is bounded by how fast the
card can stream the weights: **192 GB/s ÷ model size ≈ theoretical ceiling in tok/s**.
Real throughput lands well below that. On this rig none of the nine tested models was
fully resident (section 8), so treat the ceiling as an upper bound that has not been
reached here.

```
2.5 GB model  ->  theoretical ~77 tok/s   ->  expect meaningfully less in practice
5.0 GB model  ->  theoretical ~38 tok/s   ->  expect meaningfully less in practice
```

Two things follow:

- Overclocking the i7-8700 will not speed up a fully-GPU-resident model. It only helps
  once layers have spilled to CPU.
- **Halving the model size roughly doubles the speed.** This is why Tier 1 is the default.

## 6. When layers spill, the CPU side becomes the bottleneck

For `hunter-max`, the ~45% of layers living in system RAM are limited by DDR4 bandwidth
(roughly 40 GB/s dual-channel) and by the i7-8700's AVX2 throughput. Two things help:

- **Confirm your RAM is running in dual-channel.** Two sticks in the correct slots. A
  32 GB single-stick configuration halves memory bandwidth and roughly halves your
  CPU-side token rate. Check in Task Manager → Performance → Memory → "Slots used".
- Leave `num_thread` at Ollama's default. The i7-8700 has 6 physical cores; forcing 12
  threads onto 12 hyperthreads usually makes inference slower, not faster.

## 7. Windows-specific

- **Don't let the 1060 drive a 4K monitor while inferencing** if you can avoid it. Desktop
  composition at high resolution can cost several hundred MB of VRAM — which is exactly
  the margin Tier 2 is operating on.
- Close the browser before running Tier 2. Modern browsers with hardware acceleration
  routinely hold 500 MB+ of VRAM.
- Check the real free VRAM before loading:
  ```powershell
  nvidia-smi --query-gpu=memory.total,memory.used,memory.free --format=csv
  ```
- Keep models off a mechanical drive. First-load time is dominated by disk read; an SSD
  turns a 9 GB Tier 3 load from minutes into seconds.

## 8. Measured VRAM placement (corrects an earlier estimate)

An earlier version of these notes, and of the README and model-selection doc, assumed
~5.0-5.3 GB of usable VRAM and that models of about 4.8 GB or less would sit 100% on the
GPU. **The measurements say otherwise.** Source:
`results/bench-2026-09-19-gtx1060.json` (GTX 1060 6 GB, 6144 MiB total, Ollama 0.34.2),
placement from Ollama's `/api/ps`; weight sizes from the model blobs in `~/.ollama`.
All figures MiB.

| Model | Weights | Loaded total | On GPU | Spilled to RAM | gen tok/s |
|---|---:|---:|---:|---:|---:|
| mistral:7b | 4170 | 4826 | 4437 | 389 | 18.6 |
| qwen2.5:7b | 4466 | 4879 | 4418 | 461 | 23.8 |
| qwen2.5-coder:7b | 4466 | 4879 | 4418 | 461 | 23.3 |
| huihui_ai/qwen2.5-abliterate:7b | 4466 | 4879 | 4418 | 461 | 23.8 |
| deepseek-r1:7b | 4466 | 4879 | 4418 | 461 | 22.2 |
| dolphin3:8b | 4693 | 5349 | 4320 | 1029 | 13.3 |
| llama3.1:8b | 4693 | 5349 | 4320 | 1029 | 12.8 |
| qwen3:8b | 4983 | 5685 | 4392 | 1293 | 11.1 |
| deepseek-r1:8b | 4983 | - | - | - | 10.2 |

"Loaded total" is Ollama's reported size for the loaded model: weights plus KV cache plus
compute buffers. `deepseek-r1:8b` has **no placement data**: its `/api/ps` lookup returned
nothing (`in_vram` is `null`, not `false`), so eight of the nine models are measured as not
fully resident and the ninth is unknown.

What the numbers show:

- **The GPU-resident portion topped out at 4320-4437 MiB regardless of model.** That is
  about 4.2-4.3 GiB of a 6.0 GiB card. Roughly 1.7 GiB was not available to Ollama.
- **The old arithmetic counted too little on both sides.** The KV cache and compute
  buffers add 413-702 MiB on top of the weights at the bench's context length (the
  bench does not record it), against the ~0.2 GB the old ~5.0 GB-weights / ~5.2 GB-budget
  figures left for them. And the budget itself was overstated by roughly 0.8-0.9 GiB.
- **The missing ~1.7 GiB is measured, but not apportioned.** The WDDM/desktop reserve,
  the CUDA context, and Ollama's own per-GPU headroom all plausibly contribute. This
  bench cannot separate them; do not quote a figure for any one.
- **Even the smallest model spilled.** `mistral:7b` has the smallest weights (4170 MiB) and
  still left 389 MiB in system RAM.
- **Spill tracks throughput.** The models that spilled 1-1.3 GiB run at 11-13 tok/s; the
  ones that spilled ~0.4-0.5 GiB run at 19-24 tok/s. The bandwidth ceiling in section 5
  was not reached by any of them.

What this does not show: whether `q8_0` KV cache, a smaller `num_ctx`, closing the
browser, or a different display setup would move any of these models to 100% GPU. None of
those were varied. Until measured, "fits fully on the GPU" is an untested claim for every
model in this table.

## Quick reference

| Setting | Value on this machine | Reason |
|---|---|---|
| Quantization | `Q4_K_M` | i-quants are slower on Pascal |
| KV cache type | `q8_0` | Halves cache VRAM, negligible quality cost |
| Flash attention | **measure it** | Not a guaranteed win pre-Turing |
| Max fully-GPU model | **not established** | No tested model fit; ~4.3-4.4 GiB reached the GPU (section 8) |
| CUDA line | 12.x only | CUDA 13 dropped CC 6.1 |
| Threads | Ollama default | 6 physical cores; oversubscription hurts |
