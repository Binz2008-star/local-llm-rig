# CLAUDE.md

Read [`HANDOFF.md`](HANDOFF.md) first, before planning or editing. It carries current
state, which measurements are trustworthy, the ordered next actions, and the coordination
rules for this repo. Update it before you stop working.

This repo is a local LLM benchmarking rig, not a product. Its only value is that its
numbers are real, so:

- Never publish a number you have not measured on this hardware.
- Read the raw JSON in `results/`, not the summary table. Every bug found here so far
  produced a clean, plausible summary.
- State what a measurement does not prove.

Edit in the git clone and copy to the flat run folder, never the reverse — `HANDOFF.md`
has the paths and the commands.
