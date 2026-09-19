# OpenCode config

`opencode.jsonc` is a copy of the live OpenCode config, kept here so the setup is
reproducible.

**The live file goes at `~/.config/opencode/opencode.jsonc`** (on Windows,
`%USERPROFILE%\.config\opencode\opencode.jsonc`). Copy it there:

```powershell
New-Item -ItemType Directory -Force "$HOME\.config\opencode" | Out-Null
Copy-Item "$HOME\local-llm-rig-repo\opencode\opencode.jsonc" "$HOME\.config\opencode\opencode.jsonc" -Force
```

What it sets up: `qwen2.5-coder:7b` as the default model, plus
`huihui_ai/qwen2.5-abliterate:7b`, both served by the local Ollama, with 8192 context and
4096 output. Both models must already be pulled.

The live file is the one OpenCode reads. If you change it, copy it back here and commit.
This template contains no credentials and no machine-specific paths; keep it that way.
