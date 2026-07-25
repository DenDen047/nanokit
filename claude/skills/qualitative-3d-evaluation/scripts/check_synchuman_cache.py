"""Validate whether an existing SyncHuman result is safe to reuse."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


CACHE_MISS_EXIT = 10


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def resolve(case_dir: Path, value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else case_dir / path


def nested(data: dict[str, Any], *keys: str) -> Any:
    current: Any = data
    for key in keys:
        if not isinstance(current, dict) or key not in current:
            return None
        current = current[key]
    return current


def check_cache(args: argparse.Namespace) -> dict[str, Any]:
    case_dir = args.case_dir.resolve()
    input_path = resolve(case_dir, args.input)
    cached_input_path = resolve(case_dir, args.cached_input)
    output_path = resolve(case_dir, args.output)
    provenance_path = resolve(case_dir, args.provenance)
    reasons: list[str] = []

    required = {
        "input": input_path,
        "cached_input": cached_input_path,
        "output": output_path,
        "provenance": provenance_path,
    }
    for label, path in required.items():
        if not path.is_file():
            reasons.append(f"{label} missing: {path}")
        elif label != "provenance" and path.stat().st_size == 0:
            reasons.append(f"{label} is empty: {path}")

    provenance: dict[str, Any] = {}
    if provenance_path.is_file():
        try:
            loaded = json.loads(provenance_path.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                provenance = loaded
            else:
                reasons.append("provenance root is not an object")
        except (OSError, json.JSONDecodeError) as error:
            reasons.append(f"provenance unreadable: {error}")

    input_sha = sha256_file(input_path) if input_path.is_file() else None
    cached_input_sha = (
        sha256_file(cached_input_path) if cached_input_path.is_file() else None
    )
    output_sha = sha256_file(output_path) if output_path.is_file() else None

    expected_pairs = [
        ("input bytes", cached_input_sha, input_sha),
        ("provenance input SHA-256", nested(provenance, "input", "sha256"), input_sha),
        (
            "repository commit",
            nested(provenance, "synchuman", "repository_commit"),
            args.repository_commit,
        ),
        (
            "checkpoint revision",
            nested(provenance, "synchuman", "checkpoint_repository_revision"),
            args.checkpoint_revision,
        ),
        ("seed", nested(provenance, "synchuman", "seed"), args.seed),
        (
            "output SHA-256",
            nested(provenance, "synchuman", "output", "sha256"),
            output_sha,
        ),
    ]
    if args.stage_one_sha256:
        expected_pairs.append(
            (
                "OneStage checkpoint-tree SHA-256",
                nested(
                    provenance,
                    "synchuman",
                    "checkpoint_tree_sha256",
                    "OneStage",
                ),
                args.stage_one_sha256,
            )
        )
    if args.stage_two_sha256:
        expected_pairs.append(
            (
                "SecondStage checkpoint-tree SHA-256",
                nested(
                    provenance,
                    "synchuman",
                    "checkpoint_tree_sha256",
                    "SecondStage",
                ),
                args.stage_two_sha256,
            )
        )

    for label, actual, expected in expected_pairs:
        if actual != expected:
            reasons.append(f"{label} mismatch: expected {expected!r}, found {actual!r}")

    hit = not reasons
    return {
        "cache": "hit" if hit else "miss",
        "reuse": hit,
        "case_dir": str(case_dir),
        "input_sha256": input_sha,
        "output": str(output_path),
        "output_sha256": output_sha,
        "reasons": reasons,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case_dir", type=Path)
    parser.add_argument("--input", default="input_gt.png")
    parser.add_argument("--cached-input", default="synchuman/input.png")
    parser.add_argument("--output", default="synchuman/model.glb")
    parser.add_argument("--provenance", default="provenance.json")
    parser.add_argument("--repository-commit", required=True)
    parser.add_argument("--checkpoint-revision", required=True)
    parser.add_argument("--seed", type=int, default=43)
    parser.add_argument("--stage-one-sha256")
    parser.add_argument("--stage-two-sha256")
    args = parser.parse_args()

    result = check_cache(args)
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0 if result["reuse"] else CACHE_MISS_EXIT


if __name__ == "__main__":
    raise SystemExit(main())
