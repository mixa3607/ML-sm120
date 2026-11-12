import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class BuildTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for name in ["basalt", ".build", "bin"]:
            (self.root / name).mkdir()
        for name in ["git-common.sh", "logger.sh", "build-common.sh"]:
            shutil.copy2(ROOT / ".build" / name, self.root / ".build" / name)
        self.script = self.root / "basalt/build-and-push.image.sh"
        shutil.copy2(ROOT / "basalt/build-and-push.image.sh", self.script)
        docker = self.root / "bin/docker"
        docker.write_text(
            '#!/usr/bin/env python3\n'
            'import json, os, sys\n'
            'with open(os.environ["DOCKER_CALLS"], "a") as output:\n'
            '    output.write(json.dumps(sys.argv[1:]) + "\\n")\n'
            'if sys.argv[1:3] == ["buildx", "build"]:\n'
            '    sys.exit(int(os.environ.get("BUILD_STATUS", "0")))\n'
            'if sys.argv[-1] in json.loads(os.environ.get("MISSING_IMAGES", "[]")):\n'
            '    print("manifest unknown", file=sys.stderr)\n'
            '    sys.exit(1)\n'
            'if os.environ.get("LOOKUP_ERROR"):\n'
            '    print("unauthorized: authentication required", file=sys.stderr)\n'
            '    sys.exit(1)\n'
        )
        docker.chmod(0o755)
        self.calls = self.root / "docker-calls.jsonl"
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith("BASALT_")
        }
        self.env.update({
            "PATH": f"{self.root / 'bin'}:{os.environ['PATH']}",
            "DOCKER_CALLS": str(self.calls),
            "REPO_GIT_REF": "test",
            "BASALT_IMAGE": "test/basalt",
            "BASALT_BASE_IMAGE": "test/cuda:devel",
            "BASALT_RUNTIME_IMAGE": "test/cuda:runtime",
            "BASALT_PUSH": "0",
        })

    def run_script(self, *args, **overrides):
        return subprocess.run(
            ["bash", str(self.script), *args],
            env={**self.env, **overrides}, capture_output=True, text=True,
        )

    def docker_calls(self):
        if not self.calls.exists():
            return []
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def test_build_defaults(self):
        result = self.run_script("build")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.docker_calls()
        self.assertEqual(calls[:2], [
            ["buildx", "imagetools", "inspect", "test/cuda:devel"],
            ["buildx", "imagetools", "inspect", "test/cuda:runtime"],
        ])
        build = calls[-1]
        self.assertEqual(build[:2], ["buildx", "build"])
        for arg in ["CUDA_ARCH=120", "BASALT_BRANCH=v0.3.2", "BUILD_JOBS=4",
                    "CCACHE_MAXSIZE=2G", "linux/amd64",
                    "test/basalt:v0.3.2-cuda-13.4.3-test-pre"]:
            self.assertIn(arg, build)
        self.assertNotIn("--push", build)

    def test_release_tags_push_and_overrides(self):
        result = self.run_script(
            "build", BASALT_IS_RELEASE="1", BASALT_PUSH="1",
            BASALT_PRESET_NAME="custom", BASALT_COMMIT="abc123",
            BASALT_BUILD_JOBS="2", BASALT_CUDA_ARCH="120-real",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        build = self.docker_calls()[-1]
        for arg in ["--push", "test/basalt:custom-test", "test/basalt:custom",
                    "BASALT_COMMIT=abc123", "BUILD_JOBS=2", "CUDA_ARCH=120-real"]:
            self.assertIn(arg, build)
        self.assertEqual(build.count("--tag"), 2)

    def test_commit_in_default_tag(self):
        result = self.run_script("check", BASALT_COMMIT="abc123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.docker_calls()[0][-1],
                         "test/basalt:abc123-cuda-13.4.3-test-pre")

    def test_push_enabled_by_default(self):
        self.env.pop("BASALT_PUSH")
        result = self.run_script("build")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--push", self.docker_calls()[-1])

    def test_branch_slash_in_default_tag(self):
        result = self.run_script("check", BASALT_BRANCH="feature/test")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.docker_calls()[0][-1],
                         "test/basalt:feature-test-cuda-13.4.3-test-pre")

    def test_check_existing_image(self):
        result = self.run_script("check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "false\n")
        self.assertEqual(len(self.docker_calls()), 1)

    def test_check_missing_image(self):
        result = self.run_script("check", MISSING_IMAGES=json.dumps([
            "test/basalt:v0.3.2-cuda-13.4.3-test-pre",
        ]))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "true\n")

    def test_force_check_without_registry(self):
        result = self.run_script("check", BASALT_FORCE_BUILD="1", LOOKUP_ERROR="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "true\n")
        self.assertEqual(self.docker_calls(), [])

    def test_lookup_error_is_not_missing(self):
        result = self.run_script(LOOKUP_ERROR="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("true", result.stdout)
        self.assertIn("unauthorized", result.stderr)
        self.assertEqual(len(self.docker_calls()), 1)

    def test_default_skips_existing_image(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.docker_calls()), 1)

    def test_default_builds_missing_image(self):
        result = self.run_script(MISSING_IMAGES=json.dumps([
            "test/basalt:v0.3.2-cuda-13.4.3-test-pre",
        ]))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.docker_calls()[-1][:2], ["buildx", "build"])

    def test_missing_base_stops_build(self):
        for image in ["test/cuda:devel", "test/cuda:runtime"]:
            with self.subTest(image=image):
                result = self.run_script("build", MISSING_IMAGES=json.dumps([image]))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Required base image", result.stderr)
        self.assertFalse(any(call[:2] == ["buildx", "build"]
                             for call in self.docker_calls()))

    def test_force_build_still_checks_bases(self):
        result = self.run_script(
            BASALT_FORCE_BUILD="1", MISSING_IMAGES='["test/cuda:runtime"]',
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.docker_calls()[-1][-1], "test/cuda:runtime")

    def test_base_lookup_error_stops_build(self):
        result = self.run_script("build", LOOKUP_ERROR="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unauthorized", result.stderr)
        self.assertEqual(len(self.docker_calls()), 1)

    def test_build_failure_survives_tee(self):
        result = self.run_script("build", BUILD_STATUS="7")
        self.assertEqual(result.returncode, 7)

    def test_invalid_command(self):
        for args in [("invalid",), ("check", "build")]:
            with self.subTest(args=args):
                result = self.run_script(*args)
                self.assertEqual(result.returncode, 2)
        self.assertEqual(self.docker_calls(), [])


if __name__ == "__main__":
    unittest.main()
