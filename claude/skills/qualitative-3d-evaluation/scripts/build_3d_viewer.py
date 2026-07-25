"""Build a synchronized qualitative-comparison GLB viewer from JSON."""

from __future__ import annotations

import argparse
import html
import json
import math
import os
import re
from pathlib import Path
from string import Template
from typing import Any
from urllib.parse import quote


MODEL_ID = re.compile(r"[A-Za-z][A-Za-z0-9_-]*\Z")
MODEL_VIEWER_URL = (
    "https://ajax.googleapis.com/ajax/libs/model-viewer/4.0.0/"
    "model-viewer.min.js"
)


def require_object(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be an object")
    return value


def require_text(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} must be a non-empty string")
    return value


def asset_url(raw: Any, manifest_dir: Path, output_dir: Path, label: str) -> str:
    path = Path(require_text(raw, label))
    resolved = path if path.is_absolute() else manifest_dir / path
    resolved = resolved.resolve()
    if not resolved.is_file() or resolved.stat().st_size == 0:
        raise ValueError(f"{label} is missing or empty: {resolved}")
    relative = os.path.relpath(resolved, output_dir.resolve())
    return quote(Path(relative).as_posix(), safe="/._-")


def finite_number(value: Any, label: str) -> float:
    if not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f"{label} must be a finite number")
    return float(value)


def build(manifest_path: Path, output_path: Path) -> dict[str, Any]:
    data = require_object(
        json.loads(manifest_path.read_text(encoding="utf-8")), "manifest"
    )
    manifest_dir = manifest_path.resolve().parent
    output_dir = output_path.resolve().parent
    title = require_text(data.get("title"), "title")
    description = require_text(data.get("description"), "description")
    note = require_text(data.get("note"), "note")
    input_data = require_object(data.get("input"), "input")
    input_url = asset_url(
        input_data.get("src"), manifest_dir, output_dir, "input.src"
    )
    input_alt = require_text(input_data.get("alt"), "input.alt")
    input_caption = require_text(input_data.get("caption"), "input.caption")

    viewer = require_object(data.get("viewer", {}), "viewer")
    columns = viewer.get("columns", 3)
    if not isinstance(columns, int) or not 1 <= columns <= 4:
        raise ValueError("viewer.columns must be an integer from 1 to 4")
    polar = finite_number(viewer.get("polar_degrees", 75), "viewer.polar_degrees")
    initial_yaw = finite_number(
        viewer.get("initial_yaw_degrees", 0), "viewer.initial_yaw_degrees"
    )

    models = data.get("models")
    if not isinstance(models, list) or not models:
        raise ValueError("models must be a non-empty array")
    seen_ids: set[str] = set()
    articles: list[str] = []
    model_configs: list[dict[str, Any]] = []
    for index, raw_model in enumerate(models):
        model = require_object(raw_model, f"models[{index}]")
        model_id = require_text(model.get("id"), f"models[{index}].id")
        if not MODEL_ID.fullmatch(model_id):
            raise ValueError(f"models[{index}].id is not HTML-safe: {model_id!r}")
        if model_id in seen_ids:
            raise ValueError(f"duplicate model id: {model_id}")
        seen_ids.add(model_id)
        name = require_text(model.get("name"), f"models[{index}].name")
        alt = require_text(model.get("alt"), f"models[{index}].alt")
        source = asset_url(
            model.get("src"), manifest_dir, output_dir, f"models[{index}].src"
        )
        yaw_offset = finite_number(
            model.get("yaw_offset_degrees", 0),
            f"models[{index}].yaw_offset_degrees",
        )
        metrics = require_object(model.get("metrics", {}), f"models[{index}].metrics")
        metric_html = "".join(
            f"<span>{html.escape(require_text(label, 'metric label'))}</span>"
            f"<strong>{html.escape(str(value))}</strong>"
            for label, value in metrics.items()
        )
        initial_orbit = initial_yaw + yaw_offset
        articles.append(
            f"""
      <article>
        <div class="heading">
          <div class="heading-top">
            <h2>{html.escape(name)}</h2>
            <span id="{model_id}-status" class="status">読み込み中</span>
          </div>
          <div class="metric">{metric_html}</div>
        </div>
        <model-viewer id="{model_id}" src="{source}" alt="{html.escape(alt)}"
          camera-controls interaction-prompt="none"
          camera-orbit="{initial_orbit:g}deg {polar:g}deg auto"
          shadow-intensity="1.2" environment-image="neutral"
          exposure="1.05"></model-viewer>
      </article>"""
        )
        model_configs.append({"id": model_id, "yawOffset": yaw_offset})

    # Escape "<" so a model ID can never terminate the inline script.
    configs_json = json.dumps(model_configs, ensure_ascii=False).replace("<", "\\u003c")
    page = PAGE_TEMPLATE.substitute(
        title=html.escape(title),
        description=html.escape(description),
        input_url=input_url,
        input_alt=html.escape(input_alt),
        input_caption=html.escape(input_caption),
        model_count=len(models),
        columns=columns,
        articles="\n".join(articles),
        note=html.escape(note),
        initial_yaw=f"{initial_yaw:g}",
        polar=f"{polar:g}",
        configs_json=configs_json,
        model_viewer_url=MODEL_VIEWER_URL,
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(page, encoding="utf-8")
    return {
        "output": str(output_path.resolve()),
        "models": len(models),
        "model_ids": [model["id"] for model in model_configs],
    }


PAGE_TEMPLATE = Template(
    """<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>$title — 3D比較</title>
  <script type="module" src="$model_viewer_url"></script>
  <style>
    :root {
      color-scheme: dark;
      font-family: Inter, system-ui, -apple-system, "Noto Sans JP", sans-serif;
      background: #07101d;
      color: #edf4ff;
      --line: #2b3d59;
      --muted: #a9b8cd;
      --blue: #78a9ff;
      --green: #74e0ad;
      --amber: #f2c46f;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: radial-gradient(circle at 50% 12%, #1b3151, #07101d 58%);
    }
    header {
      display: grid;
      grid-template-columns: minmax(0, 1fr) 132px;
      gap: 24px;
      align-items: center;
      padding: 22px clamp(18px, 3vw, 44px);
      border-bottom: 1px solid var(--line);
      background: #091423ed;
    }
    h1 { margin: 0 0 8px; font-size: clamp(22px, 3vw, 35px); }
    p { margin: 0; color: var(--muted); line-height: 1.65; }
    .reference {
      margin: 0;
      overflow: hidden;
      border: 1px solid #496181;
      border-radius: 10px;
      background: #000;
    }
    .reference img {
      display: block;
      width: 100%;
      aspect-ratio: 1;
      object-fit: contain;
    }
    .reference figcaption {
      padding: 6px 8px;
      color: #dbe8fa;
      background: #101d30;
      font-size: 11px;
      text-align: center;
    }
    .toolbar {
      position: sticky;
      top: 0;
      z-index: 4;
      display: flex;
      align-items: center;
      gap: 13px;
      padding: 11px clamp(18px, 3vw, 44px);
      border-bottom: 1px solid var(--line);
      background: #0a1525f2;
      backdrop-filter: blur(12px);
    }
    .toolbar label { white-space: nowrap; font-size: 13px; }
    .toolbar input { width: min(620px, 58vw); accent-color: var(--blue); }
    output {
      min-width: 3.5em;
      color: var(--green);
      font-variant-numeric: tabular-nums;
    }
    main { padding: 18px clamp(12px, 2.2vw, 34px) 28px; }
    .models {
      display: grid;
      grid-template-columns: repeat($columns, minmax(0, 1fr));
      gap: 1px;
      overflow: hidden;
      border: 1px solid var(--line);
      border-radius: 14px;
      background: var(--line);
      box-shadow: 0 20px 65px #0008;
    }
    article {
      min-width: 0;
      display: grid;
      grid-template-rows: auto 1fr;
      background: #08121f;
    }
    .heading {
      min-height: 108px;
      padding: 12px 14px;
      border-bottom: 1px solid var(--line);
      background: #0b1728e8;
    }
    .heading-top {
      display: flex;
      justify-content: space-between;
      gap: 10px;
      align-items: baseline;
    }
    h2 { margin: 0 0 8px; font-size: clamp(14px, 1.5vw, 18px); }
    .status { color: var(--amber); font-size: 11px; white-space: nowrap; }
    .status[data-state="ready"] { color: var(--green); }
    .status[data-state="error"] { color: #ff8b8b; }
    .metric {
      display: grid;
      grid-template-columns: 1fr auto;
      gap: 3px 10px;
      color: var(--muted);
      font-size: 12px;
      font-variant-numeric: tabular-nums;
    }
    .metric strong { color: #edf4ff; font-weight: 600; }
    model-viewer {
      width: 100%;
      height: min(53vh, 550px);
      min-height: 430px;
      background: radial-gradient(circle at 50% 43%, #2a405f, #0c1726 72%);
      --progress-bar-color: var(--blue);
    }
    .note {
      margin-top: 15px;
      padding: 13px 16px;
      border: 1px solid #66522d;
      border-radius: 10px;
      background: #2c2415d9;
      color: #ead8ad;
      line-height: 1.65;
      font-size: 13px;
    }
    @media (max-width: 1050px) {
      .models { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    }
    @media (max-width: 640px) {
      header { grid-template-columns: 1fr 92px; gap: 14px; }
      .models { grid-template-columns: 1fr; }
      model-viewer { height: 520px; min-height: 520px; }
    }
  </style>
</head>
<body>
  <header>
    <div>
      <h1>$title</h1>
      <p>$description</p>
    </div>
    <figure class="reference">
      <img src="$input_url" alt="$input_alt">
      <figcaption>$input_caption</figcaption>
    </figure>
  </header>
  <div class="toolbar">
    <label for="angle">$model_count体を同期回転</label>
    <input id="angle" type="range" min="-180" max="180"
      value="$initial_yaw" step="1">
    <output id="angle-value" for="angle">$initial_yaw°</output>
  </div>
  <main>
    <div class="models">
$articles
    </div>
    <div class="note">$note</div>
  </main>
  <script>
    const modelConfigs = $configs_json;
    const polar = $polar;
    const viewers = modelConfigs.map(({ id }) => document.querySelector(`#$${id}`));
    modelConfigs.forEach(({ id }, index) => {
      const status = document.querySelector(`#$${id}-status`);
      const ready = () => {
        status.textContent = '表示準備完了';
        status.dataset.state = 'ready';
      };
      const failed = () => {
        status.textContent = '読み込み失敗';
        status.dataset.state = 'error';
      };
      if (viewers[index].loaded) ready();
      viewers[index].addEventListener('load', ready);
      viewers[index].addEventListener('error', failed);
    });
    const angle = document.querySelector('#angle');
    const angleValue = document.querySelector('#angle-value');
    angle.addEventListener('input', () => {
      viewers.forEach((viewer, index) => {
        const yaw = Number(angle.value) + modelConfigs[index].yawOffset;
        viewer.cameraOrbit = `$${yaw}deg $${polar}deg auto`;
      });
      angleValue.textContent = `$${angle.value}°`;
    });
  </script>
</body>
</html>
"""
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = build(args.manifest, args.output)
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
