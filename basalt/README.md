# Basalt SM120

[Basalt](https://github.com/jesdga95/basalt), a local MoE inference engine with
OpenAI and Anthropic APIs, built explicitly for NVIDIA `sm_120` on Linux x86-64.
The host needs an AVX2 CPU, a compatible NVIDIA driver for the selected CUDA
version, and NVIDIA Container Toolkit. Building does not need a GPU.

Image name: `docker.io/mixa3607/basalt-sm120` (publication is separate from adding
this build).

## Build

From this directory:

```bash
BASALT_PUSH=0 ./build-and-push.image.sh build
```

Commands: [`check` / `build`](../.build/README.md). `BASALT_PUSH=0` leaves the
result in the builder cache; it does not load an image into the local Docker
daemon. The default command checks the output tag before building.

| Variable | Default |
| -------- | ------- |
| `BASALT_IMAGE` | `docker.io/mixa3607/basalt-sm120` |
| `BASALT_CUDA_IMAGE` | `docker.io/nvidia/cuda` |
| `BASALT_CUDA_VERSION` | `13.4.3` |
| `BASALT_CUDA_ARCH` | `120` (upstream only supports SM120) |
| `BASALT_BASE_IMAGE` | `$BASALT_CUDA_IMAGE:$BASALT_CUDA_VERSION-devel-ubuntu24.04` |
| `BASALT_RUNTIME_IMAGE` | `$BASALT_CUDA_IMAGE:$BASALT_CUDA_VERSION-runtime-ubuntu24.04` |
| `BASALT_REPO` | `https://github.com/jesdga95/basalt.git` |
| `BASALT_BRANCH` | `v0.3.2`; accepts a branch or tag |
| `BASALT_COMMIT` | empty; if set, check out this commit after cloning `BASALT_BRANCH` |
| `BASALT_BUILD_JOBS` | `4`; limits compiler memory use |
| `BASALT_CCACHE_MAXSIZE` | `2G` (BuildKit cache) |
| `BASALT_PRESET_NAME` | `$BASALT_COMMIT-cuda-$BASALT_CUDA_VERSION`, or `$BASALT_BRANCH-cuda-$BASALT_CUDA_VERSION` with `/` replaced by `-` |
| `BASALT_IS_RELEASE` | `0` |
| `BASALT_PUSH` | `1` |
| `BASALT_FORCE_BUILD` | unset; `1` forces rebuilding |
| `REPO_GIT_REF` | repository tag, otherwise short SHA |

Release tags (`BASALT_IS_RELEASE=1`): `$BASALT_PRESET_NAME-$REPO_GIT_REF` and
`$BASALT_PRESET_NAME`. Otherwise: `$BASALT_PRESET_NAME-$REPO_GIT_REF-pre`.

The CUDA 13.4.3 stack and runtime layout follow upstream's Dockerfile. The final
image uses the CUDA runtime, not the development toolkit. Python dependencies
use upstream's pinned requirements. Source SHA is printed during the build and
saved as `/opt/basalt/REVISION`; use `BASALT_COMMIT` for an immutable source pin.
Cloning follows the ComfyUI build: a shallow clone of `BASALT_BRANCH`, then an
optional commit checkout. The pinned commit must be available in that clone;
`--depth 1` does not fetch older commits in the branch history.
Base tags and OS package repositories are not digest/snapshot-pinned.

For private test images, source [`../.build/.env-local.sh`](../.build/.env-local.sh)
first, then explicitly set `BASALT_IMAGE=registry.arkprojects.space/apps/basalt-sm120`
(the local overrides may not cover Basalt). Keep test tags suffixed with `-pre`.

## Run

Mount your existing `.basalt` model files at `/models` and a writable directory
containing `basalt_config.json` at `/data`. No models are included or downloaded.
A minimal version-2 configuration:

```json
{
  "version": 2,
  "models": [{ "model": "/models/model.basalt", "gpu": "0", "kv": "int8" }],
  "server": { "port": 8080 }
}
```

After publishing or loading an image:

```bash
docker run --rm --gpus all -p 127.0.0.1:8080:8080 \
  -v "$PWD/data:/data" -v "$PWD/models:/models:ro" \
  docker.io/mixa3607/basalt-sm120:<tag>
```

The entrypoint is `basalt serve --config /data/basalt_config.json --host 0.0.0.0`.
Extra arguments are appended, for example `--api-key KEY`. Server caches and
engine logs live under `/data/.cache/basalt`. Override `--entrypoint basalt-probe`
or `--entrypoint basalt-bench` to use the other included tools.
See upstream [configuration](https://github.com/jesdga95/basalt/blob/main/docs/configuration/index.md)
for memory, multi-GPU, model, and authentication settings. GPU compatibility and
performance require a separate real-hardware test.

## CI and tests

[`basalt-daily-build.yaml`](../.github/workflows/basalt-daily-build.yaml) resolves
the latest upstream release once, or accepts `basalt_tag`, and builds CUDA 13.4.3.
It uses the existing registry-login action (Docker Hub with credentials, otherwise
GHCR). `BUILD_REF` pins checkout to the triggering SHA by default; the repository
variable `BUILD_REF` can override it, but must point to a ref containing `basalt/`.
A tagged checkout enables release tags, like the neighboring builds.

Build-script tests (no Docker daemon or GPU required), from the repository root:

```bash
python3 -m unittest discover -s basalt/tests -v
```
