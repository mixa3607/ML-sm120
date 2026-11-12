#!/usr/bin/env bash
set -eo pipefail

cd "$(dirname "$0")"
source ../.build/git-common.sh
source ../.build/logger.sh
source ../.build/build-common.sh

: "${REPO_GIT_REF:="$(git_get_current_ref)"}"
: "${BASALT_IMAGE:="docker.io/mixa3607/basalt-sm120"}"
: "${BASALT_CUDA_IMAGE:="docker.io/nvidia/cuda"}"
: "${BASALT_CUDA_VERSION:="13.4.3"}"
: "${BASALT_CUDA_ARCH:="120"}"
: "${BASALT_REPO:="https://github.com/jesdga95/basalt.git"}"
: "${BASALT_BRANCH:="v0.3.2"}"
: "${BASALT_COMMIT:=""}"
: "${BASALT_BUILD_JOBS:="4"}"
: "${BASALT_CCACHE_MAXSIZE:="2G"}"
: "${BASALT_PUSH:="1"}"
: "${BASALT_IS_RELEASE:="0"}"
: "${BASALT_BASE_IMAGE:="${BASALT_CUDA_IMAGE}:${BASALT_CUDA_VERSION}-devel-ubuntu24.04"}"
: "${BASALT_RUNTIME_IMAGE:="${BASALT_CUDA_IMAGE}:${BASALT_CUDA_VERSION}-runtime-ubuntu24.04"}"
: "${BASALT_PRESET_NAME:="${BASALT_COMMIT:-${BASALT_BRANCH//\//-}}-cuda-${BASALT_CUDA_VERSION}"}"

if [ "$BASALT_IS_RELEASE" == "1" ]; then
  IMAGE_TAGS=(
    "${BASALT_IMAGE}:${BASALT_PRESET_NAME}-${REPO_GIT_REF}"
    "${BASALT_IMAGE}:${BASALT_PRESET_NAME}"
  )
else
  IMAGE_TAGS=(
    "${BASALT_IMAGE}:${BASALT_PRESET_NAME}-${REPO_GIT_REF}-pre"
  )
fi

function check {
  build_check_image "${IMAGE_TAGS[0]}" "${BASALT_FORCE_BUILD:-0}"
}

function build {
  build_require_images "$BASALT_BASE_IMAGE" "$BASALT_RUNTIME_IMAGE"

  local -A IMAGE_ANNOTATIONS
  IMAGE_ANNOTATIONS["org.opencontainers.image.created"]="$(date --rfc-3339=seconds)"
  IMAGE_ANNOTATIONS["org.opencontainers.image.authors"]="mixa3607"
  IMAGE_ANNOTATIONS["org.opencontainers.image.source"]="https://github.com/mixa3607/ML-sm120/tree/${REPO_GIT_REF}/basalt"
  IMAGE_ANNOTATIONS["org.opencontainers.image.version"]="${REPO_GIT_REF}"
  IMAGE_ANNOTATIONS["org.opencontainers.image.title"]="Basalt sm120"
  IMAGE_ANNOTATIONS["org.opencontainers.image.base.name"]="${BASALT_RUNTIME_IMAGE}"

  print INFO "Start building Basalt image..."
  print INFO "BASALT_REPO:      ${BASALT_REPO}"
  print INFO "BASALT_BRANCH:    ${BASALT_BRANCH}"
  print INFO "BASALT_COMMIT:    ${BASALT_COMMIT}"
  print INFO "CUDA_VERSION:     ${BASALT_CUDA_VERSION}"
  print INFO "CUDA_ARCH:        ${BASALT_CUDA_ARCH}"
  print INFO "BUILD_JOBS:       ${BASALT_BUILD_JOBS}"
  print INFO "CCACHE_MAXSIZE:   ${BASALT_CCACHE_MAXSIZE}"
  print INFO "IS_RELEASE:       ${BASALT_IS_RELEASE}"

  local -a DOCKER_EXTRA_ARGS=()
  local i key
  for (( i=0; i<${#IMAGE_TAGS[@]}; i++ )); do
    print INFO "TAG:          ${IMAGE_TAGS[$i]}"
    DOCKER_EXTRA_ARGS+=(--tag "${IMAGE_TAGS[$i]}")
  done
  for key in "${!IMAGE_ANNOTATIONS[@]}"; do
    print INFO "ANNOTATION:   ${key}: ${IMAGE_ANNOTATIONS[$key]}"
    DOCKER_EXTRA_ARGS+=(--annotation "${key}=${IMAGE_ANNOTATIONS[$key]}")
  done

  DOCKER_EXTRA_ARGS+=(
    --build-arg BASE_CUDA_IMAGE="${BASALT_BASE_IMAGE}"
    --build-arg RUNTIME_CUDA_IMAGE="${BASALT_RUNTIME_IMAGE}"
    --build-arg CUDA_ARCH="${BASALT_CUDA_ARCH}"
    --build-arg BASALT_REPO="${BASALT_REPO}"
    --build-arg BASALT_BRANCH="${BASALT_BRANCH}"
    --build-arg BASALT_COMMIT="${BASALT_COMMIT}"
    --build-arg BUILD_JOBS="${BASALT_BUILD_JOBS}"
    --build-arg CCACHE_MAXSIZE="${BASALT_CCACHE_MAXSIZE}"
    --platform linux/amd64
    --progress plain
    --target final
    --file ./build-image.Dockerfile
    --pull
  )

  if [ "$BASALT_PUSH" == "1" ]; then
    DOCKER_EXTRA_ARGS+=(--push)
  fi

  mkdir -p ./logs
  docker buildx build "${DOCKER_EXTRA_ARGS[@]}" ./build-context 2>&1 | tee "./logs/build_$(date +%Y%m%d%H%M%S).log"
}

build_dispatch check build "$@"
