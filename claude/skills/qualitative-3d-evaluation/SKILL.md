---
name: qualitative-3d-evaluation
description: Builds standardized qualitative 3D experiment evaluations with a labeled front-view comparison and synchronized interactive GLB viewer containing Input, Ground Truth, experiment variants, metrics, and external baselines such as SyncHuman. Use when reporting 3D reconstruction or generation experiments, comparing checkpoints or data scales, preparing 定性評価 or 可視化結果, or reusing a previously generated SyncHuman result.
---

# Qualitative 3D evaluation

Produce one evidence board for a fixed case: a labeled front view, a synchronized
3D viewer, provenance, and an observation-based qualitative assessment.

Run every bundled Python tool through the locked pixi tasks in `pixi.toml`.

## 1. Freeze the comparison

Record the case identifier, exact input SHA-256, input-view budget, seed,
preprocessing, camera, sampler settings, coordinate convention, and evaluation
alignment. Include every experiment condition plus Input, Ground Truth when
available, the released/current baseline, and requested external baselines.

Use the fixed case named by the nearest `CLAUDE.md` or `AGENTS.md`. In Pixal3D,
use X-Humans person `00039`, `Take4`. The step is complete when every panel has
an artifact path and its protocol differences are explicit.

Run inference on the fixed case for **every** comparison condition, using the
same Input, the same preprocessing, and the same inference seed throughout, and
visualize all conditions with identical camera, render settings, and lighting.
Inspect the rendered images yourself before publishing, and put the available
Input, Ground Truth, and every condition's result into one comparison figure
that appears both in the conversation and in the final deliverable. When a
condition cannot run on the fixed case, do not substitute a different person or
frame — mark that panel `N/A` and state why.

SyncHuman is reused rather than regenerated whenever the cache gate in step 2
confirms that input, official revision, seed, and hash all match.

## 2. Gate SyncHuman through the cache

Set `SKILL_DIR` to this skill's directory. Before downloading checkpoints or
running SyncHuman, execute:

```bash
pixi run --locked --manifest-path "$SKILL_DIR/pixi.toml" \
  check-synchuman-cache CASE_DIR \
  --input INPUT \
  --repository-commit COMMIT \
  --checkpoint-revision REVISION \
  --seed 43
```

Exit `0` with `"cache": "hit"` means reuse `synchuman/model.glb` and skip all
SyncHuman setup, download, and inference. Exit `10` means generate it once with
the official pipeline, write the input/repository/checkpoint/seed/output hashes
to `provenance.json`, then rerun the same command. Treat the result as reusable
only after it returns a hit. A present folder alone is not a cache hit.

Pass `--stage-one-sha256` and `--stage-two-sha256` when the protocol pins those
checkpoint-tree hashes. Preserve an invalid or stale result until the new
result has finished and passed the cache gate. In Pixal3D, use
`run_synchuman_benchmark.py --force` only after this gate reports a validated
miss; a hit never uses `--force`.

## 3. Build the evidence board

Read [references/viewer-manifest.md](references/viewer-manifest.md) when creating
the viewer manifest. Keep display-only yaw offsets distinct from metric
alignment. Mark metrics from different protocols `N/A` and explain the boundary
instead of ranking them together.

Generate the viewer:

```bash
pixi run --locked --manifest-path "$SKILL_DIR/pixi.toml" build-3d-viewer \
  viewer_manifest.json \
  --output comparison_3d_viewer.html
```

Serve the artifact root over HTTP with the same locked environment:

```bash
pixi run --locked --manifest-path "$SKILL_DIR/pixi.toml" serve 8765 \
  --bind 127.0.0.1 \
  --directory CASE_DIR
```

Open the viewer and save a labeled front-view screenshot as the static
comparison figure.

## 4. Inspect and assess

Move the synchronized control to `0°`, `90°`, and `180°`. At every angle,
confirm that every asset reports ready and that the intended body direction
matches. Inspect the actual screenshots for:

- silhouette and body proportions;
- face, hands, feet, hair, and garment boundaries;
- topology or floating/merged geometry;
- texture, color, and identity cues;
- view consistency and characteristic failure modes.

Write concrete observations tied to visible regions. Separate fixed-case
observations from aggregate quantitative conclusions. SyncHuman remains an
external qualitative baseline unless its full evaluation protocol is identical.

## 5. Completion gate

Finish only when all of these exist and have been checked:

- labeled static comparison with Input, Ground Truth, every condition, and
  SyncHuman or an explicit `N/A`;
- interactive viewer with synchronized rotation and per-asset load state;
- front, side, and back screenshots inspected for layout and orientation;
- metrics table with incomparable cells marked `N/A`;
- provenance containing input, code/checkpoint, seed, output hashes, cache
  decision, and display-only transforms;
- concise qualitative findings plus the aggregate quantitative conclusion.

If browser rendering is unavailable, keep the artifacts and mark visual
verification pending; never claim that an unseen viewer passed.
