#!/usr/bin/env python3
"""
bench.py - token-throughput benchmark for Ollama models on this rig.

For every pulled model (or a --models subset) it:
  1. cold-loads the model and records load time (load_duration)
  2. runs a timed generation: P prompt tokens, N generated tokens
  3. reports prompt-processing tok/s, generation tok/s, TTFT & total ms
  4. checks /api/ps to see whether the model fit in VRAM or spilled to RAM

Pure Python stdlib (urllib) - no pip installs required.
Usage:
    python bench.py                       # all pulled models, defaults
    python bench.py --models qwen2.5:7b,mistral:7b
    python bench.py --prompt-tokens 1024 --gen-tokens 256

Output: bench-results.json next to this script + a console summary table.
"""

import argparse
import json
import os
import sys
import time
import urllib.request

OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")
REQUEST_TIMEOUT = 900  # generous: first model load on old GPUs is slow
DEFAULT_PROMPT_TOKENS = 512
DEFAULT_GEN_TOKENS = 128

# ~1 token ≈ 4 chars for English prose; this fixed paragraph repeats to fill the prompt.
_PROSE = (
    "The quick brown fox jumps over the lazy dog near the river bank while the "
    "morning sun rises slowly behind the hills. Local language models run on "
    "consumer hardware when the model size fits inside the graphics card memory, "
    "because inference speed is limited by memory bandwidth rather than raw "
    "compute power. Scientists measure token throughput in tokens per second and "
    "report both prompt processing speed and generation speed separately, since "
    "long documents and interactive chat place very different demands on the "
    "system. "
)


def api(path: str, payload: dict | None = None) -> dict:
    url = OLLAMA_HOST + path
    req = urllib.request.Request(url, method="POST" if payload else "GET")
    data = None
    if payload is not None:
        req.add_header("Content-Type", "application/json")
        data = json.dumps(payload).encode("utf-8")
    with urllib.request.urlopen(req, data=data, timeout=REQUEST_TIMEOUT) as resp:
        return json.loads(resp.read().decode("utf-8"))


def list_models() -> list[str]:
    tags = api("/api/tags")
    return sorted(m["name"] for m in tags.get("models", []))


def make_prompt(target_tokens: int) -> str:
    # ~4 chars/token for English prose. NOTE: slice by CHARACTERS, then the
    # tokenizer decides the real count; 512 tokens ≈ 2048 chars.
    chars_needed = target_tokens * 4
    return (_PROSE * (chars_needed // len(_PROSE) + 1))[:chars_needed]


def generate(model: str, prompt: str, gen_tokens: int) -> dict:
    return api(
        "/api/generate",
        {
            "model": model,
            "prompt": prompt,
            "stream": False,
            "options": {"num_predict": gen_tokens, "temperature": 0.0, "seed": 42},
        },
    )


def ns_to_ms(ns: int | None) -> float:
    return (ns or 0) / 1e6


def bench_model(model: str, prompt_tokens: int, gen_tokens: int) -> dict:
    prompt = make_prompt(prompt_tokens)

    # --- warmup pass: forces the load, measures cold-load time, warms KV cache
    t0 = time.perf_counter()
    warm = generate(model, "Say hello in one word.", 8)
    wall_warm_s = time.perf_counter() - t0
    cold_load_ms = ns_to_ms(warm.get("load_duration"))

    # --- timed pass: steady-state throughput (model still warm)
    t0 = time.perf_counter()
    run = generate(model, prompt, gen_tokens)
    wall_timed_s = time.perf_counter() - t0

    pe_count = run.get("prompt_eval_count", 0)
    pe_dur_ns = run.get("prompt_eval_duration", 0)
    e_count = run.get("eval_count", 0)
    e_dur_ns = run.get("eval_duration", 0)

    prompt_tok_s = pe_count / (pe_dur_ns / 1e9) if pe_dur_ns else None
    gen_tok_s = e_count / (e_dur_ns / 1e9) if e_dur_ns else None
    ttft_ms = ns_to_ms(pe_dur_ns)  # time spent burning the prompt = time to first token

    # --- VRAM placement via /api/ps
    placement = {"in_vram": None, "vram_mb": None, "total_mb": None}
    try:
        ps = api("/api/ps")
        # Ollama reports ":latest" for an untagged pull, so normalise both sides.
        # Matching on the family prefix instead would attribute qwen2.5-coder's
        # placement to qwen2.5, and deepseek-r1:8b's to deepseek-r1:7b.
        def _tagged(name: str) -> str:
            return name if ":" in name else f"{name}:latest"

        for m in ps.get("models", []):
            if _tagged(m["name"]) == _tagged(model):
                placement = {
                    "in_vram": bool(m.get("size_vram", 0)) and m.get("size_vram", 0) >= m.get("size", 0) * 0.999,
                    "vram_mb": round((m.get("size_vram") or 0) / (1024 * 1024), 0),
                    "total_mb": round((m.get("size") or 0) / (1024 * 1024), 0),
                }
                break
    except Exception:
        pass

    return {
        "model": model,
        "prompt_tokens_requested": prompt_tokens,
        "gen_tokens_requested": gen_tokens,
        "prompt_eval_count": pe_count,
        "eval_count": e_count,
        "prompt_tok_s": round(prompt_tok_s, 2) if prompt_tok_s else None,
        "gen_tok_s": round(gen_tok_s, 2) if gen_tok_s else None,
        "ttft_ms": round(ttft_ms, 1),
        "total_ms": round(ns_to_ms(run.get("total_duration")), 1),
        "cold_load_ms": round(cold_load_ms, 1),
        "wall_warmup_s": round(wall_warm_s, 2),
        "wall_timed_s": round(wall_timed_s, 2),
        "vram": placement,
    }


def fmt_row(r: dict) -> str:
    g = f"{r['gen_tok_s']:>7.1f}" if r["gen_tok_s"] else "     -"
    p = f"{r['prompt_tok_s']:>7.1f}" if r["prompt_tok_s"] else "     -"
    ttft = f"{r['ttft_ms']:>7.0f}"
    vram = "VRAM" if r["vram"]["in_vram"] else ("RAM" if r["vram"]["in_vram"] is False else "  ?")
    return f"{r['model']:<32} {p} {g} {ttft} {vram}"


def main() -> int:
    ap = argparse.ArgumentParser(description="Benchmark Ollama models on this rig.")
    ap.add_argument("--models", help="comma-separated subset of models to bench")
    ap.add_argument("--prompt-tokens", type=int, default=DEFAULT_PROMPT_TOKENS)
    ap.add_argument("--gen-tokens", type=int, default=DEFAULT_GEN_TOKENS)
    args = ap.parse_args()

    all_models = list_models()
    if not all_models:
        print("No models found - run `ollama pull <name>` first.", file=sys.stderr)
        return 1

    models = all_models
    if args.models:
        wanted = [m.strip() for m in args.models.split(",") if m.strip()]
        missing = [m for m in wanted if m not in all_models]
        if missing:
            print(f"Unknown models (not in `ollama list`): {missing}", file=sys.stderr)
            return 1
        models = wanted

    print(f"Benchmarking {len(models)} model(s) on {OLLAMA_HOST}")
    print(f"prompt={args.prompt_tokens} tokens | gen={args.gen_tokens} tokens | temp=0\n")

    results = []
    for i, model in enumerate(models, 1):
        print(f"[{i}/{len(models)}] {model} ... (this can take a minute)", flush=True)
        try:
            r = bench_model(model, args.prompt_tokens, args.gen_tokens)
            results.append(r)
            print("  " + fmt_row(r))
        except Exception as exc:  # keep going if a model errors (bad tag etc.)
            print(f"  !! failed: {exc}", file=sys.stderr)
            results.append({"model": model, "error": str(exc)})
        sys.stdout.flush()

    print("\n=== SUMMARY (prompt tok/s | gen tok/s | TTFT ms | placement) ===")
    for r in results:
        if "error" not in r:
            print("  " + fmt_row(r))
        else:
            print(f"  {r['model']:<32} ERROR: {r['error']}")

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bench-results.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump({
            "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
            # Placement numbers are meaningless without this: an f16 KV cache
            # is twice the size of q8_0, so the same model spills differently.
            "kv_cache_type": os.environ.get("OLLAMA_KV_CACHE_TYPE") or "unset (f16 default)",
            "results": results,
        }, f, indent=2)
    print(f"\nSaved {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())