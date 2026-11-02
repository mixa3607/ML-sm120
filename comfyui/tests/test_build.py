import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class BuildTests(unittest.TestCase):
    def test_sageattention_jobs_default_and_override(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "comfyui").mkdir()
            (root / ".build").mkdir()
            (root / "bin").mkdir()
            for name in ["git-common.sh", "logger.sh", "build-common.sh"]:
                shutil.copy2(ROOT / ".build" / name, root / ".build" / name)
            script = root / "comfyui/build-and-push.image.sh"
            shutil.copy2(ROOT / "comfyui/build-and-push.image.sh", script)
            docker = root / "bin/docker"
            docker.write_text(
                '#!/usr/bin/env python3\nimport json, os, sys\n'
                'with open(os.environ["DOCKER_CALLS"], "a") as output:\n'
                '    output.write(json.dumps(sys.argv[1:]) + "\\n")\n'
            )
            docker.chmod(0o755)
            calls = root / "docker-calls.jsonl"
            env = {**os.environ, "PATH": f"{root / 'bin'}:{os.environ['PATH']}",
                   "DOCKER_CALLS": str(calls), "COMFYUI_PUSH": "0",
                   "COMFYUI_BASE_IMAGE": "test/torch:local", "REPO_GIT_REF": "test"}
            env.pop("SAGEATTENTION_MAX_JOBS", None)
            for value in [None, "32"]:
                with self.subTest(jobs=value):
                    if value is not None:
                        env["SAGEATTENTION_MAX_JOBS"] = value
                    subprocess.run(["bash", str(script), "build"], env=env,
                                   capture_output=True, text=True, check=True)
                    build = json.loads(calls.read_text().splitlines()[-1])
                    self.assertEqual(build[:2], ["buildx", "build"])
                    self.assertIn(f"SAGEATTENTION_MAX_JOBS={value or '2'}", build)
                    self.assertNotIn("--push", build)


if __name__ == "__main__":
    unittest.main()
