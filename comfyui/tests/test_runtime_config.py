import configparser
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import venv
import zipfile


CONTEXT = Path(__file__).resolve().parents[1] / "build-context"
spec = importlib.util.spec_from_file_location("runtime_config", CONTEXT / "runtime_config.py")
runtime_config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime_config)


class RuntimeConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_manager_overrides_preserve_other_settings(self):
        path = self.root / "user/__manager/config.ini"
        path.parent.mkdir(parents=True)
        path.write_text("[default]\nuse_uv = True\nchannel_url = https://example.org/%20\n"
                        "[other]\nvalue = keep\n")
        with patch.dict(os.environ, {
            "COMFYMANAGER_use_uv": "False",
            "COMFYMANAGER_use_unified_resolver": "False",
            "COMFYMANAGER_network_mode": "offline",
        }, clear=True):
            runtime_config.configure_manager(["--enable-manager", "--base-directory", str(self.root)])
            before = path.stat().st_mtime_ns
            runtime_config.configure_manager([f"--base-directory={self.root}"])
        config = configparser.ConfigParser(interpolation=None)
        config.read(path)
        self.assertEqual(config["default"]["use_uv"], "False")
        self.assertEqual(config["default"]["use_unified_resolver"], "False")
        self.assertEqual(config["default"]["network_mode"], "offline")
        self.assertEqual(config["default"]["channel_url"], "https://example.org/%20")
        self.assertEqual(config["other"]["value"], "keep")
        self.assertEqual(path.stat().st_mtime_ns, before)

    def test_manager_uses_last_base_and_explicit_user_directory(self):
        user = self.root / "custom-user"
        with patch.dict(os.environ, {"COMFYMANAGER_use_uv": "False"}, clear=True):
            runtime_config.configure_manager([
                "--base-directory=/unused", f"--base-directory={self.root}",
            ])
            runtime_config.configure_manager([
                "--base-directory=/unused", "--user-directory", str(user),
                "--listen=0.0.0.0", "--port", "8188",
            ])
        self.assertTrue((self.root / "user/__manager/config.ini").exists())
        self.assertTrue((user / "__manager/config.ini").exists())

    def test_manager_without_overrides_does_not_create_config(self):
        with patch.dict(os.environ, {}, clear=True):
            runtime_config.configure_manager([f"--base-directory={self.root}"])
        self.assertFalse((self.root / "user").exists())

    def test_manager_rejects_invalid_key_and_invalid_saved_config(self):
        with patch.dict(os.environ, {"COMFYMANAGER_": "False"}, clear=True):
            with self.assertRaises(ValueError):
                runtime_config.configure_manager([])
        path = self.root / "user/__manager/config.ini"
        path.parent.mkdir(parents=True)
        path.write_text("not an INI file\n")
        with patch.dict(os.environ, {"COMFYMANAGER_use_uv": "False"}, clear=True):
            with self.assertRaises(configparser.Error):
                runtime_config.configure_manager([f"--base-directory={self.root}"])
        self.assertEqual(path.read_text(), "not an INI file\n")

    def test_constraints_preserve_cuda_versions_and_detect_stack_changes(self):
        packages = {"torch": "2.14.1+cu132", "torchvision": "0.29.1+cu132",
                    "torchaudio": "2.11.0", "triton": "3.8.0",
                    "nvidia_cublas_cu13": "13.2.0", "cuda-bindings": "13.2.0",
                    "requests": "2.32.0"}
        path = self.root / "gpu-constraints.txt"

        def distributions():
            return [SimpleNamespace(metadata={"Name": name}, version=version)
                    for name, version in packages.items()]

        with patch.object(runtime_config.importlib.metadata, "distributions", distributions):
            runtime_config.write_gpu_constraints(path)
            packages["sageattention"] = "2.2.0"
            packages["sageattn3"] = "1.0.0"
            runtime_config.write_gpu_constraints(path)
            text = path.read_text()
            self.assertIn("torch==2.14.1+cu132\n", text)
            self.assertIn("nvidia-cublas-cu13==13.2.0\n", text)
            self.assertIn("cuda-bindings==13.2.0\n", text)
            self.assertIn("sageattention==2.2.0\n", text)
            self.assertIn("sageattn3==1.0.0\n", text)
            self.assertNotIn("requests", text)
            packages["torch"] = "2.14.1+cu130"
            with self.assertRaisesRegex(RuntimeError, "GPU package changed"):
                runtime_config.write_gpu_constraints(path)
            self.assertEqual(path.read_text(), text)
            del packages["torch"]
            with self.assertRaisesRegex(RuntimeError, "must provide torch"):
                runtime_config.write_gpu_constraints(path)

    def test_entrypoint_bootstrap_applies_environment_and_keeps_extra_constraints(self):
        app = self.root / "app"
        app.mkdir()
        for name in ["models", "custom_nodes", "input", "output"]:
            (app / name).mkdir()
        (app / "runtime_config.py").write_text((CONTEXT / "runtime_config.py").read_text())
        (app / "gpu-constraints.txt").write_text("torch==2.14.1+cu132\n")
        (app / "entrypoint.sh").write_text(
            (CONTEXT / "entrypoint.sh").read_text().replace("/opt/comfyui", str(app))
        )
        # Capture the exported constraints after running the real bootstrap logic.
        (app / "capture.sh").write_text(
            'source ./entrypoint.sh\nprintf "%s\\n%s\\n" "$PIP_CONSTRAINT" "$UV_CONSTRAINT"\n'
        )
        env = {**os.environ, "BOOTSTRAP_ONLY": "1", "VENV_NAME": "",
               "PERSISTENCE_PATH": str(self.root / "data"),
               "COMFYMANAGER_use_uv": "False", "COMFYMANAGER_use_unified_resolver": "False",
               "PIP_CONSTRAINT": "/extra/pip.txt", "UV_CONSTRAINT": "/extra/uv.txt"}
        (self.root / "data").mkdir()
        result = subprocess.run(["bash", "./capture.sh"], cwd=app, env=env,
                                text=True, capture_output=True, check=True)
        self.assertIn(f"{app}/gpu-constraints.txt /extra/pip.txt", result.stdout)
        self.assertIn(f"{app}/gpu-constraints.txt /extra/uv.txt", result.stdout)
        self.assertTrue((self.root / "data/user/__manager/config.ini").exists())
        env.update(PERSISTENCE_PATH="", PIP_CONSTRAINT=str(app / "gpu-constraints.txt"),
                   UV_CONSTRAINT=str(app / "gpu-constraints.txt"))
        result = subprocess.run(["bash", "./capture.sh"], cwd=app, env=env,
                                text=True, capture_output=True, check=True)
        self.assertEqual(result.stdout.splitlines()[-2:], [str(app / "gpu-constraints.txt")] * 2)
        self.assertTrue((app / "user/__manager/config.ini").exists())

        (app / "main.py").write_text(
            'import json, os, sys\n'
            'print(json.dumps({"python": sys.executable, "cwd": os.getcwd(), "args": sys.argv}))\n'
        )
        env.update(BOOTSTRAP_ONLY="0", VENV_NAME=".test-venv")
        user = self.root / "custom-user"
        result = subprocess.run([
            "bash", str(app / "entrypoint.sh"), "--user-directory", str(user),
        ], cwd=self.root, env=env, text=True, capture_output=True, check=True)
        started = json.loads(result.stdout.splitlines()[-1])
        self.assertEqual(started["python"], str(app / ".test-venv/bin/python3"))
        self.assertEqual(started["cwd"], str(app))
        self.assertIn("--enable-manager", started["args"])
        self.assertTrue((user / "__manager/config.ini").exists())

    def test_pip_reuses_inherited_torch_and_rejects_conflicting_plugin(self):
        environment = self.root / "venv"
        venv.create(environment, with_pip=True, system_site_packages=True)
        python = environment / "bin/python3"
        site_packages = next((environment / "lib").glob("python*/site-packages"))
        inherited = self.root / "image-site-packages"
        metadata = inherited / "torch-2.14.1+cu132.dist-info"
        metadata.mkdir(parents=True)
        (metadata / "METADATA").write_text("Metadata-Version: 2.1\nName: torch\nVersion: 2.14.1+cu132\n")
        (site_packages / "image.pth").write_text(str(inherited) + "\n")
        constraints = self.root / "gpu-constraints.txt"
        constraints.write_text("torch==2.14.1+cu132\n")
        env = {**os.environ, "PIP_CONSTRAINT": str(constraints), "PIP_CONFIG_FILE": os.devnull,
               "PIP_DISABLE_PIP_VERSION_CHECK": "1"}

        for requirement, success in [("torch>=2.10", True), ("torch<2.10", False)]:
            wheel = self.root / "test_plugin-1.0-py3-none-any.whl"
            with zipfile.ZipFile(wheel, "w") as archive:
                archive.writestr("test_plugin-1.0.dist-info/METADATA",
                                 "Metadata-Version: 2.1\nName: test-plugin\nVersion: 1.0\n"
                                 f"Requires-Dist: {requirement}\n")
                archive.writestr("test_plugin-1.0.dist-info/WHEEL",
                                 "Wheel-Version: 1.0\nRoot-Is-Purelib: true\nTag: py3-none-any\n")
                archive.writestr("test_plugin-1.0.dist-info/RECORD", "")
            result = subprocess.run([
                str(python), "-m", "pip", "install", "--dry-run", "--no-index",
                "--no-cache-dir", str(wheel),
            ], env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
            if success:
                self.assertIn("Requirement already satisfied: torch", result.stdout)
                self.assertIn("Would install test-plugin-1.0", result.stdout)
            else:
                self.assertIn("ResolutionImpossible", result.stderr)
        self.assertFalse(any(site_packages.glob("torch*")))


if __name__ == "__main__":
    unittest.main()
