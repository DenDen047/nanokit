from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SKILL_DIR = Path(__file__).resolve().parents[1]
CACHE_TOOL = SKILL_DIR / "scripts" / "check_synchuman_cache.py"
VIEWER_TOOL = SKILL_DIR / "scripts" / "build_3d_viewer.py"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class SyncHumanCacheTests(unittest.TestCase):
    def test_hit_and_seed_miss(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_dir:
            case_dir = Path(temporary_dir)
            synchuman_dir = case_dir / "synchuman"
            synchuman_dir.mkdir()
            input_path = case_dir / "input_gt.png"
            cached_input_path = synchuman_dir / "input.png"
            output_path = synchuman_dir / "model.glb"
            input_path.write_bytes(b"fixed input")
            cached_input_path.write_bytes(input_path.read_bytes())
            output_path.write_bytes(b"fixed output")
            provenance = {
                "input": {"sha256": sha256(input_path)},
                "synchuman": {
                    "repository_commit": "repo-commit",
                    "checkpoint_repository_revision": "checkpoint-revision",
                    "seed": 43,
                    "output": {"sha256": sha256(output_path)},
                },
            }
            (case_dir / "provenance.json").write_text(
                json.dumps(provenance), encoding="utf-8"
            )

            common = [
                sys.executable,
                str(CACHE_TOOL),
                str(case_dir),
                "--repository-commit",
                "repo-commit",
                "--checkpoint-revision",
                "checkpoint-revision",
            ]
            hit = subprocess.run(common, capture_output=True, text=True, check=False)
            self.assertEqual(hit.returncode, 0, hit.stderr)
            self.assertEqual(json.loads(hit.stdout)["cache"], "hit")

            miss = subprocess.run(
                [*common, "--seed", "44"],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(miss.returncode, 10, miss.stderr)
            miss_result = json.loads(miss.stdout)
            self.assertEqual(miss_result["cache"], "miss")
            self.assertTrue(
                any("seed mismatch" in reason for reason in miss_result["reasons"])
            )


class ViewerBuilderTests(unittest.TestCase):
    def test_builds_synchronized_viewer(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_dir:
            case_dir = Path(temporary_dir)
            (case_dir / "input.png").write_bytes(b"input")
            (case_dir / "model.glb").write_bytes(b"model")
            manifest = {
                "title": "Fixed qualitative case",
                "description": "Same input and rendering protocol.",
                "input": {
                    "src": "input.png",
                    "alt": "Fixed input",
                    "caption": "Input",
                },
                "models": [
                    {
                        "id": "candidate",
                        "name": "Candidate",
                        "src": "model.glb",
                        "alt": "Candidate reconstruction",
                        "yaw_offset_degrees": 15,
                        "metrics": {"Protocol": "fixed"},
                    }
                ],
                "note": "SyncHuman metrics are N/A when protocols differ.",
                "viewer": {
                    "columns": 1,
                    "polar_degrees": 75,
                    "initial_yaw_degrees": 0,
                },
            }
            manifest_path = case_dir / "viewer_manifest.json"
            output_path = case_dir / "comparison_3d_viewer.html"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            completed = subprocess.run(
                [
                    sys.executable,
                    str(VIEWER_TOOL),
                    str(manifest_path),
                    "--output",
                    str(output_path),
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(json.loads(completed.stdout)["model_ids"], ["candidate"])
            page = output_path.read_text(encoding="utf-8")
            self.assertIn("<model-viewer id=\"candidate\"", page)
            self.assertIn('camera-orbit="15deg 75deg auto"', page)
            self.assertIn('id="angle"', page)


if __name__ == "__main__":
    unittest.main()
