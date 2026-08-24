# ML software for SM120 arch

![GitHub License](https://img.shields.io/github/license/mixa3607/ML-sm120?style=flat-square)

## Subprojects

| Name      | About               | Artefacts | Status                                                                                                                                                | Docs                            |
| --------- | ------------------- | --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------- |
| llama.cpp | llama.cpp images    | image     | ![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/mixa3607/ML-sm120/llamacpp-daily-build.yaml?style=flat-square) | [readme](./llama.cpp/README.md) |
| ComfyUI   | ComfyUI images      | image     | ![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/mixa3607/ML-sm120/comfyui-daily-build.yaml?style=flat-square)  | [readme](./comfyui/README.md)   |

## Prebuilt images

| Project   | Image                                                                                                                             |
| --------- | --------------------------------------------------------------------------------------------------------------------------------- |
| llama.cpp | [`docker.io/mixa3607/llama.cpp-sm120:<ver>-cuda-13.3.0-cudnn`](https://hub.docker.com/r/mixa3607/llama.cpp-sm120/tags)\* |
| ComfyUI   | [`docker.io/mixa3607/comfyui-sm120:<ver>-cuda-13.2-cudnn9`](https://hub.docker.com/r/mixa3607/comfyui-sm120/tags)\*      |

> \* llama.cpp and ComfyUI have daily builds. See last tag on dockerhub

## Deps graph

```mermaid
flowchart TD
  torch[docker.io/pytorch/pytorch] --> comfyui[docker.io/mixa3607/comfyui-sm120]
  cuda[docker.io/nvidia/cuda] --> llama[docker.io/mixa3607/llama.cpp-sm120]
```
