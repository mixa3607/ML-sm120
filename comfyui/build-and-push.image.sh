#!/usr/bin/env bash
set -eo pipefail

cd "$(dirname "$0")"
source ../.build/git-common.sh
source ../.build/logger.sh
source ../.build/build-common.sh

: "${REPO_GIT_REF:="$(git_get_current_ref)"}"
: "${COMFYUI_IMAGE:="docker.io/mixa3607/comfyui-sm120"}"
: "${COMFYUI_TORCH_IMAGE:="docker.io/pytorch/pytorch"}"
: "${COMFYUI_CUDA_VERSION:="13.2-cudnn9"}"
: "${COMFYUI_PYTORCH_VERSION:="2.13.0"}"
: "${COMFYUI_REPO:="https://github.com/Comfy-Org/ComfyUI.git"}"
: "${COMFYUI_BRANCH:="master"}"
: "${COMFYUI_COMMIT:=""}"
: "${SAGEATTENTION_REPO:="https://github.com/thu-ml/SageAttention.git"}"
: "${SAGEATTENTION_REF:="v2.2.0"}"
: "${COMFYUI_PUSH:="1"}"
: "${COMFYUI_IS_RELEASE:="0"}"
: "${COMFYUI_BASE_IMAGE:="${COMFYUI_TORCH_IMAGE}:${COMFYUI_PYTORCH_VERSION}-cuda${COMFYUI_CUDA_VERSION}-runtime"}"

if [ "$COMFYUI_IS_RELEASE" == "1" ]; then
  IMAGE_TAGS=(
    "$COMFYUI_IMAGE:${COMFYUI_BRANCH}-torch-${COMFYUI_PYTORCH_VERSION}-cuda-${COMFYUI_CUDA_VERSION}-${REPO_GIT_REF}"
    "$COMFYUI_IMAGE:${COMFYUI_BRANCH}-torch-${COMFYUI_PYTORCH_VERSION}-cuda-${COMFYUI_CUDA_VERSION}"
    "$COMFYUI_IMAGE:${COMFYUI_BRANCH}-cuda-${COMFYUI_CUDA_VERSION}-${REPO_GIT_REF}"
    "$COMFYUI_IMAGE:${COMFYUI_BRANCH}-cuda-${COMFYUI_CUDA_VERSION}"
    "$COMFYUI_IMAGE:latest-cuda-${COMFYUI_CUDA_VERSION}"
  )
else
  IMAGE_TAGS=(
    "$COMFYUI_IMAGE:${COMFYUI_BRANCH}-torch-${COMFYUI_PYTORCH_VERSION}-cuda-${COMFYUI_CUDA_VERSION}-${REPO_GIT_REF}-pre"
  )
fi

function check {
  build_check_image "${IMAGE_TAGS[0]}" "${COMFYUI_FORCE_BUILD:-0}"
}

function build {
  build_require_images "$COMFYUI_BASE_IMAGE"

  local CUDA_TOOLKIT_VERSION="${COMFYUI_CUDA_VERSION%%-*}"
  local -A IMAGE_ANNOTATIONS
  IMAGE_ANNOTATIONS["org.opencontainers.image.created"]="$(date --rfc-3339=seconds)"
  IMAGE_ANNOTATIONS["org.opencontainers.image.authors"]="mixa3607"
  IMAGE_ANNOTATIONS["org.opencontainers.image.source"]="https://github.com/mixa3607/ML-sm120/tree/${REPO_GIT_REF}/comfyui"
  IMAGE_ANNOTATIONS["org.opencontainers.image.version"]="${REPO_GIT_REF}"
  IMAGE_ANNOTATIONS["org.opencontainers.image.title"]="ComfyUI sm120"
  IMAGE_ANNOTATIONS["org.opencontainers.image.base.name"]="${COMFYUI_BASE_IMAGE}"

  print INFO "Start building ComfyUI image..."
  print INFO "REPO:          ${COMFYUI_REPO}"
  print INFO "VERSION:       ${COMFYUI_BRANCH}"
  print INFO "COMMIT:        ${COMFYUI_COMMIT}"
  print INFO "CUDA_VERSION:  ${COMFYUI_CUDA_VERSION}"
  print INFO "TORCH_VERSION: ${COMFYUI_PYTORCH_VERSION}"
  print INFO "SAGEATTENTION: ${SAGEATTENTION_REPO} (${SAGEATTENTION_REF})"
  print INFO "IS_RELEASE:    ${COMFYUI_IS_RELEASE}"

  local -a DOCKER_EXTRA_ARGS=()
  local i key
  for (( i=0; i<${#IMAGE_TAGS[@]}; i++ )); do
    print INFO "TAG:          ${IMAGE_TAGS[$i]}"
    DOCKER_EXTRA_ARGS+=("--tag" "${IMAGE_TAGS[$i]}")
  done
  for key in "${!IMAGE_ANNOTATIONS[@]}"; do
    print INFO "ANNOTATION:   ${key}: ${IMAGE_ANNOTATIONS[$key]}"
    DOCKER_EXTRA_ARGS+=("--annotation" "${key}=${IMAGE_ANNOTATIONS[$key]}")
  done

  DOCKER_EXTRA_ARGS+=(
    --build-arg BASE_PYTORCH_IMAGE="${COMFYUI_BASE_IMAGE}"
    --build-arg COMFY_REPO="${COMFYUI_REPO}"
    --build-arg COMFY_BRANCH="${COMFYUI_BRANCH}"
    --build-arg COMFY_COMMIT="${COMFYUI_COMMIT}"
    --build-arg SAGEATTENTION_REPO="${SAGEATTENTION_REPO}"
    --build-arg SAGEATTENTION_REF="${SAGEATTENTION_REF}"
    --build-arg CUDA_TOOLKIT_PACKAGE="cuda-toolkit-${CUDA_TOOLKIT_VERSION//./-}"
    --progress plain
    --target final
    --file ./build-image.Dockerfile
    --pull
  )

  if [ "$COMFYUI_PUSH" == "1" ]; then
    DOCKER_EXTRA_ARGS+=(--push)
  fi

  mkdir -p ./logs
  print INFO "Install ComfyUI to image"
  docker buildx build "${DOCKER_EXTRA_ARGS[@]}" ./build-context 2>&1 | tee "./logs/build_$(date +%Y%m%d%H%M%S).log"
}

build_dispatch check build "$@"
