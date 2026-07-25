# Viewer manifest

Create one JSON object next to the case artifacts:

```json
{
  "title": "X-Humans 00039 / Take4 / f00063",
  "description": "Ground Truth, experiment variants, and SyncHuman.",
  "input": {
    "src": "input_gt.png",
    "alt": "Fixed front input",
    "caption": "Common front Input"
  },
  "models": [
    {
      "id": "gt",
      "name": "Ground Truth",
      "src": "ground_truth.glb",
      "alt": "Ground Truth 3D",
      "yaw_offset_degrees": 0,
      "metrics": {
        "Data": "X-Humans mesh",
        "Frame": "f00063"
      }
    },
    {
      "id": "released",
      "name": "Released",
      "src": "released/model.glb",
      "alt": "Released model reconstruction",
      "yaw_offset_degrees": 180,
      "metrics": {
        "Chamfer-L1": "0.0134050",
        "F-score @2%": "0.774215"
      }
    },
    {
      "id": "synchuman",
      "name": "SyncHuman official",
      "src": "synchuman/model.glb",
      "alt": "Official SyncHuman reconstruction",
      "yaw_offset_degrees": 0,
      "metrics": {
        "Input": "same front image",
        "Protocol": "Two-stage / seed 43"
      }
    }
  ],
  "note": "SyncHuman is an external qualitative baseline. Its metrics are N/A because the evaluation protocol differs.",
  "viewer": {
    "columns": 3,
    "polar_degrees": 75,
    "initial_yaw_degrees": 0
  }
}
```

## Rules

- Resolve `input.src` and every `models[].src` relative to the manifest.
- Use unique HTML-safe model IDs: a letter followed by letters, digits, `_`, or
  `-`.
- Express metrics as display labels and strings. Put `N/A` in the table/report,
  not a fabricated value.
- Use `yaw_offset_degrees` only to align the visible front in the viewer. Record
  it separately from evaluation alignment in provenance.
- Keep the note explicit about input budgets, seeds, preprocessing, coordinate
  systems, and protocol differences.
