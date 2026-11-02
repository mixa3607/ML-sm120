# ComfyUI SM120

[ComfyUI](https://github.com/Comfy-Org/ComfyUI) with SageAttention 2/2++
(`sageattention`) and SageAttention 3 (`sageattn3`) built for `sm_120`.

Images: [docker.io/mixa3607/comfyui-sm120](https://hub.docker.com/r/mixa3607/comfyui-sm120/tags).

## Run

```bash
docker run --rm --gpus all -p 8188:8188 \
  -e PERSISTENCE_PATH=/data -v "$(pwd)/data:/data" \
  docker.io/mixa3607/comfyui-sm120:<tag> --use-sage-attention
```

| Variable           | Effect                                                                                                               |
| ------------------ | -------------------------------------------------------------------------------------------------------------------- |
| `PERSISTENCE_PATH` | Copy `models`, `custom_nodes`, `input`, `output` here; use as `--base-directory`; SQLite DB at `database/comfyui.db` |
| `VENV_NAME`        | Venv with `--system-site-packages` at `$PERSISTENCE_PATH/$VENV_NAME`, or `/opt/comfyui/$VENV_NAME` without persistence |
| `BOOTSTRAP_ONLY=1` | Prepare persistence/venv without starting ComfyUI                                                                    |
| `COMFYMANAGER_<key>` | Set `<key>` in the Manager's `[default]` configuration section before startup; overrides the saved value |
| `COMFYMANAGER_use_uv` | `False`; use pip so dependencies already available through system site-packages are reused |
| `COMFYMANAGER_use_unified_resolver` | `False`; disable the Manager's uv-based batch resolver |

ComfyUI is installed at `/opt/comfyui`. The image sets `LANG=C.UTF-8` and
`LC_ALL=C.UTF-8`.

Manager overrides are also applied with `BOOTSTRAP_ONLY=1`. The configuration
is at `$PERSISTENCE_PATH/user/__manager/config.ini`, or
`/opt/comfyui/user/__manager/config.ini` without persistence. Explicit
`--base-directory` and `--user-directory` arguments are respected. Other saved
configuration values are retained. For example, `COMFYMANAGER_network_mode=offline`
sets `network_mode = offline`.

The entrypoint adds `--enable-manager`. `--use-sage-attention` selects
SageAttention 2/2++; SageAttention 3 requires model/node integration through
`sageattn3.sageattn3_blackwell`.

### GPU dependency constraints

The image generates `/opt/comfyui/gpu-constraints.txt` from installed package
metadata, preserving full versions including CUDA suffixes. It pins Torch,
TorchVision, TorchAudio, Triton, installed `nvidia-*` / `cuda-*` packages, and
the SageAttention extensions. The base stack is constrained before installing
ComfyUI dependencies and checked again after installing SageAttention.

Both `PIP_CONSTRAINT` and `UV_CONSTRAINT` include this file; the entrypoint
also retains additional constraint files supplied through these variables.
Incompatible plugin requirements fail resolution instead of replacing the GPU
stack. Other dependencies can still be installed in the venv. Constraints are
not a sandbox: plugin installers can bypass them. Enabling `use_uv` again can
still duplicate system packages, even with pinned versions.

Existing persistent venvs are not cleaned or migrated automatically. If one
already shadows the image's GPU packages, use a new `VENV_NAME` and reinstall
the custom-node dependencies, keeping the old environment for rollback.

## Build

```bash
COMFYUI_BRANCH=v0.38.0 COMFYUI_PUSH=0 ./build-and-push.image.sh
```

Defaults: [`build-and-push.image.sh`](./build-and-push.image.sh).
Commands: [`check` / `build`](../.build/README.md).

| Variable                  | Default                                                                           |
| ------------------------- | --------------------------------------------------------------------------------- |
| `COMFYUI_IMAGE`           | `docker.io/mixa3607/comfyui-sm120`                                                |
| `COMFYUI_TORCH_IMAGE`     | `docker.io/pytorch/pytorch`                                                       |
| `COMFYUI_CUDA_VERSION`    | `13.2-cudnn9`                                                                     |
| `COMFYUI_PYTORCH_VERSION` | `2.13.0`                                                                          |
| `COMFYUI_BASE_IMAGE`      | `$COMFYUI_TORCH_IMAGE:$COMFYUI_PYTORCH_VERSION-cuda$COMFYUI_CUDA_VERSION-runtime` |
| `COMFYUI_REPO`            | `https://github.com/Comfy-Org/ComfyUI.git`                                        |
| `COMFYUI_BRANCH`          | `master`                                                                          |
| `COMFYUI_COMMIT`          | empty                                                                             |
| `SAGEATTENTION_REPO`      | `https://github.com/thu-ml/SageAttention.git`                                     |
| `SAGEATTENTION_REF`       | `v2.2.0`, shared by both wheels                                                   |
| `COMFYUI_IS_RELEASE`      | `0`                                                                               |
| `COMFYUI_PUSH`            | `1`                                                                               |
| `COMFYUI_FORCE_BUILD`     | unset; `1` forces rebuild                                                         |
| `REPO_GIT_REF`            | git tag, otherwise short SHA                                                      |

SageAttention is built with the matching CUDA toolkit in a separate stage;
the final image uses the PyTorch runtime base.

Release tags (`COMFYUI_IS_RELEASE=1`), omitting the `COMFYUI_` variable prefix:

- `$BRANCH-torch-$PYTORCH_VERSION-cuda-$CUDA_VERSION-$REPO_GIT_REF`
- `$BRANCH-torch-$PYTORCH_VERSION-cuda-$CUDA_VERSION`
- `$BRANCH-cuda-$CUDA_VERSION-$REPO_GIT_REF`
- `$BRANCH-cuda-$CUDA_VERSION`
- `latest-cuda-$CUDA_VERSION`

Otherwise: `$BRANCH-torch-$PYTORCH_VERSION-cuda-$CUDA_VERSION-$REPO_GIT_REF-pre`.

Registry overrides: [`../.build/.env-local.sh`](../.build/.env-local.sh).

## Tests

From the repository root:

```bash
python3 -B -m unittest discover -s comfyui/tests -v
bash -n comfyui/build-context/entrypoint.sh comfyui/build-and-push.image.sh
```

These CPU-only checks cover Manager configuration, bootstrap paths, generated
constraints, and offline pip resolution with lightweight fake package metadata.
They do not validate GPU runtime compatibility.
