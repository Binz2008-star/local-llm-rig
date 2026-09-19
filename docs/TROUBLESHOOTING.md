# Troubleshooting

## `ollama ps` says something other than `100% GPU`

The model did not fit. In order of what to try:

1. Close the browser and anything else using the GPU, then check real free VRAM:
   `nvidia-smi --query-gpu=memory.free --format=csv`
2. Set `OLLAMA_KV_CACHE_TYPE=q8_0` and restart Ollama (see below) — the f16 cache is twice
   the size and can be the difference between a split and a full fit.
3. Lower `num_ctx` in the Modelfile and rebuild.
4. Drop to a model that fits. A fully-GPU model at full speed beats a split one.

Placement has only been measured once on this rig and that measurement had a known
bug (`results/README.md`), so treat "does it fit" as an open question until re-measured.

## Everything is suddenly ~5x slower after an Ollama update

Almost certainly the GPU stopped being used. Run `scripts/doctor.ps1`. If it reports the
GPU is missing, this is the CUDA 13 / Pascal hazard described in `HARDWARE_NOTES.md` —
reinstall the previous Ollama version.

Confirm directly while a model is loaded:

```powershell
nvidia-smi          # is there an ollama process holding VRAM?
ollama ps           # what split does Ollama report?
```

## Environment variables don't seem to take effect

Ollama on Windows runs as a background service started at login. It reads its environment
at start, so a variable set in your current shell is invisible to it.

```powershell
setx OLLAMA_KV_CACHE_TYPE "q8_0"     # persists for future processes
# then fully restart Ollama:
Get-Process ollama* -ErrorAction SilentlyContinue | Stop-Process -Force
# relaunch Ollama from the Start menu (or log out and back in)
```

Verify it took:

```powershell
[Environment]::GetEnvironmentVariable("OLLAMA_KV_CACHE_TYPE", "User")
```

## Out of memory / model fails to load

```
Error: model requires more system memory than is available
```

For Tier 3 this usually means something large is already resident. `ollama ps` shows
what is loaded; `ollama stop <model>` unloads it. Ollama keeps a model in memory for
5 minutes by default — set `OLLAMA_KEEP_ALIVE=30s` if you are switching between tiers a
lot and running into this.

## The model still refuses things

Refusal behaviour is specific to the base model, so it varies by model even at the same
size. On this rig, only one of the four probed 7B models refused anything: `qwen2.5-coder`
(3/15 — dark fiction, blunt tone, a history detail). In order of what to try:

1. **Switch to the measured safe model.** `qwen2.5:7b` scored 0 refusals across two
   independent runs. If your workflow will not leave coders alone, keep `qwen2.5-coder`
   for code and take sensitive prompts to `qwen2.5:7b` — that is measured to work.
2. **Reformulate rather than argue.** Restating the request usually beats trying to talk
   the model out of a refusal in a follow-up turn.
3. **Confirm the model you think you are running.** `ollama ps` shows what is actually
   loaded.

If a whole category is being refused, measure it rather than guessing:

```powershell
python .\scripts\refusal-probe.py --all --show
```

That gives you refusal and hedge rates per model side by side, and `--show` prints the
responses so you can see whether it is a hard refusal or the classifier miscounting.

## Refusal rates look identical across every model

Check the responses with `--show`. Two likely causes: the probe set is not hitting the
categories you actually care about (extend `probes/false-refusal.json` with your own
prompts — that is what it is for), or the models never loaded and every probe errored.

## The refusal probe says 0% but the model still annoys me

Look at the hedge column. A model can answer everything and still wrap each answer in
disclaimers. On this rig that behaviour is measured: `qwen2.5:7b` and `mistral:7b` hedge
2/15, `qwen2.5-coder` 1/15, and the abliterate twin 0/15. If a model's hedging annoys you,
check whether you are setting a system prompt that invites moralizing — otherwise try a
different model; the hedge column is in the probe output precisely so you can compare.

## `bench.py` can't connect

```
Cannot reach Ollama at http://127.0.0.1:11434
```

Ollama isn't running, or it is bound elsewhere. Start it from the Start menu, then:

```powershell
curl http://127.0.0.1:11434/api/version
```

If you set `OLLAMA_HOST`, pass the same value: `python .\scripts\bench.py --all --host http://...`

## Downloads are slow or keep stalling

`ollama pull` resumes — just re-run the same command. Tier 3 is a ~9 GB download; expect
it to take a while.

## First response after loading is very slow, then it speeds up

Normal. That is the model being read from disk into VRAM plus prompt processing. It only
happens on a cold load. `bench.py` runs a warmup pass before timing for exactly this
reason.
