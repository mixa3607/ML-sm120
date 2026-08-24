#/bin/bash

pushd $(dirname ${BASH_SOURCE[0]})

if [ "$LLAMA_IMAGE" == "" ]; then
  LLAMA_IMAGE=docker.io/mixa3607/llama.cpp-sm120
fi

# cuda ver
if [ "$LLAMA_CUDA_VERSION" == "" ]; then
  LLAMA_CUDA_VERSION=13.3.0-cudnn
fi
# cuda base image
if [ "$LLAMA_CUDA_IMAGE" == "" ]; then
  LLAMA_CUDA_IMAGE=docker.io/nvidia/cuda
fi
# target arch
if [ "$LLAMA_CUDA_ARCH" == "" ]; then
  LLAMA_CUDA_ARCH=120
fi

if [ "$LLAMA_REPO" == "" ]; then
  LLAMA_REPO="https://github.com/ggml-org/llama.cpp.git"
fi
if [ "$LLAMA_BRANCH" == "" ]; then
  LLAMA_BRANCH="master"
fi
if [ "$LLAMA_COMMIT" == "" ]; then
  LLAMA_COMMIT=""
fi
if [ "$LLAMA_CCACHE_MAXSIZE" == "" ]; then
  LLAMA_CCACHE_MAXSIZE="2G"
fi
if [ "$LLAMA_IS_RELEASE" == "" ]; then
  LLAMA_IS_RELEASE="0"
fi
if [ "$LLAMA_PATCH" == "" ]; then
  LLAMA_PATCH="empty.patch"
fi

# push image
if [ "$LLAMA_PUSH" == "" ]; then
  LLAMA_PUSH="1"
fi

popd
