# Tests

Pure-function regression tests for the probe classifier. No network, no GPU, no
Ollama — they run anywhere, including CI on every push.

```bash
python -m pytest tests/ -v
```

Each test pins a bug that shipped, produced a clean-looking results table, and
was caught only by reading raw model answers. The list of those bugs is in
`../HANDOFF.md`. A test here is how each one is kept from returning — most were
lost when the probe was rewritten shorter, so the tests exist to make the next
rewrite fail loudly instead of silently dropping a safeguard.

Add a test here whenever you touch `classify`, `split_thinking`, or
`load_questions`, and whenever a new classification bug is found.
