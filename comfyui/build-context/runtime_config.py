import argparse
import configparser
import importlib.metadata
import os
from pathlib import Path
import re
import sys


def write_gpu_constraints(path):
    protected = {"torch", "torchvision", "torchaudio", "triton", "sageattention", "sageattn3"}
    versions = {}
    for distribution in importlib.metadata.distributions():
        name = re.sub(r"[-_.]+", "-", distribution.metadata["Name"]).lower()
        if name in protected or name.startswith(("nvidia-", "cuda-")):
            versions[name] = distribution.version

    if "torch" not in versions:
        raise RuntimeError("The base image must provide torch")

    # Keep the base stack unchanged when adding the final image's GPU extensions.
    if path.exists():
        for line in path.read_text().splitlines():
            if line and not line.startswith("#"):
                name, version = line.split("==", 1)
                if versions.get(name) != version:
                    raise RuntimeError(f"GPU package changed during the build: {line}")

    path.write_text(
        "# GPU stack provided by this image; generated from installed metadata.\n"
        + "".join(f"{name}=={version}\n" for name, version in sorted(versions.items()))
    )


def configure_manager(arguments):
    overrides = {key.removeprefix("COMFYMANAGER_"): value
                 for key, value in os.environ.items() if key.startswith("COMFYMANAGER_")}
    if not overrides:
        return
    for key in overrides:
        if not re.fullmatch(r"[a-zA-Z0-9_]+", key):
            raise ValueError(f"Invalid ComfyUI-Manager configuration key: {key!r}")

    parser = argparse.ArgumentParser(add_help=False, allow_abbrev=False)
    parser.add_argument("--base-directory", default=str(Path(__file__).resolve().parent))
    parser.add_argument("--user-directory")
    args, _ = parser.parse_known_args(arguments)
    user_directory = Path(args.user_directory) if args.user_directory else Path(args.base_directory) / "user"
    path = user_directory / "__manager" / "config.ini"

    config = configparser.ConfigParser(interpolation=None, strict=False)
    config.read(path, encoding="utf-8")
    if not config.has_section("default"):
        config.add_section("default")
    changed = False
    for key, value in sorted(overrides.items()):
        if config.get("default", key, fallback=None) != value:
            config.set("default", key, value)
            print(f"ComfyUI-Manager: applying {key} from environment")
            changed = True
    if changed:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("w", encoding="utf-8") as output:
            config.write(output)


if __name__ == "__main__":
    if sys.argv[1] == "constraints":
        write_gpu_constraints(Path(sys.argv[2]))
    elif sys.argv[1] == "manager":
        configure_manager(sys.argv[2:])
    else:
        raise ValueError(f"Unknown configuration command: {sys.argv[1]}")
