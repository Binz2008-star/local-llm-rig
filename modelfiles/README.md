# Modelfiles

**Every file here is an untested proposal.** None has been built or run.

| File | Base image (`FROM`) | Installed on the reference rig? |
|---|---|---|
| `hunter-open.Modelfile` | `goekdenizguelmez/JOSIEFIED-Qwen3:8b-q4_k_m` | no |
| `hunter-open-fast.Modelfile` | `goekdenizguelmez/JOSIEFIED-Qwen3:4b-q4_k_m` | no |
| `hunter-dolphin.Modelfile` | `huihui_ai/dolphin3-abliterated:8b` | no |
| `hunter-max.Modelfile` | `huihui_ai/qwen3-abliterated:14b-v2-q4_K_M` | no |

The comments inside each file (how open it is, whether it fits on the GPU, how fast it is)
are design intent, not results. The VRAM-fit figures in particular predate
`docs/HARDWARE_NOTES.md` section 8, where no tested 7-8B model fit fully on the 6 GB card.

## Why they are kept here rather than deleted or moved

`scripts/setup.ps1` builds from this directory by name, and the READMEs and
`docs/MODEL_SELECTION.md` still name the `hunter-*` variants — now explicitly as the
untested lineage, ineligible for the measured ranking. Deleting or moving the files would
break `setup.ps1` without measurement having decided anything. They stay in place,
labelled, until a real run shows which models are worth building.

What has actually been measured is the nine models in
`results/bench-2026-09-19-gtx1060.json`. If a `hunter-*` variant is ever built and tested,
record it in `results/` and remove its banner in the same commit.
