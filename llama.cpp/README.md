# llama.cpp SM120

[llama.cpp](https://github.com/ggml-org/llama.cpp) with CUDA `sm_120` support.

Images: [docker.io/mixa3607/llama.cpp-sm120](https://hub.docker.com/r/mixa3607/llama.cpp-sm120/tags).

## Build

```bash
LLAMA_BRANCH=b10612 \
LLAMA_PRESET_NAME=b10612-cuda-13.3.0-cudnn \
LLAMA_PUSH=0 ./build-and-push.image.sh
```

Defaults: [`build-and-push.image.sh`](./build-and-push.image.sh).
Commands: [`check` / `build`](../.build/README.md).

| Variable                          | Default                                                   |
| --------------------------------- | --------------------------------------------------------- |
| `LLAMA_IMAGE`                     | `docker.io/mixa3607/llama.cpp-sm120`                      |
| `LLAMA_CUDA_IMAGE`                | `docker.io/nvidia/cuda`                                   |
| `LLAMA_CUDA_VERSION`              | `13.3.0-cudnn`                                            |
| `LLAMA_CUDA_ARCH`                 | `120`                                                     |
| `LLAMA_BASE_IMAGE`                | `$LLAMA_CUDA_IMAGE:$LLAMA_CUDA_VERSION-devel-ubuntu24.04` |
| `LLAMA_REPO`                      | `https://github.com/ggml-org/llama.cpp.git`               |
| `LLAMA_BRANCH`                    | `master`                                                  |
| `LLAMA_COMMIT`, `LLAMA_CODE_PATH` | empty                                                     |
| `LLAMA_PATCH`                     | `empty.patch`, relative to `build-context/patch/`         |
| `LLAMA_CCACHE_MAXSIZE`            | `2G` (BuildKit cache)                                     |
| `LLAMA_PRESET_NAME`               | required tag prefix                                       |
| `LLAMA_IS_RELEASE`                | `0`                                                       |
| `LLAMA_PUSH`                      | `1`                                                       |
| `LLAMA_FORCE_BUILD`               | unset; `1` forces rebuild                                 |
| `REPO_GIT_REF`                    | git tag, otherwise short SHA                              |

Release tags (`LLAMA_IS_RELEASE=1`): `$LLAMA_PRESET_NAME-$REPO_GIT_REF`
and `$LLAMA_PRESET_NAME`. Otherwise: `$LLAMA_PRESET_NAME-$REPO_GIT_REF-pre`.

Registry overrides: [`../.build/.env-local.sh`](../.build/.env-local.sh).
