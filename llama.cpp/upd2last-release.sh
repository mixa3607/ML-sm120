RELEASE_TAG="$(curl -L \
  -H "Accept: application/vnd.github+json" \
  'https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=1' | yq -r '.[0].tag_name')"

PRESET=preset.$RELEASE_TAG-cuda-13.3.0-cudnn.sh
if ! [ -f "$PRESET" ]; then
  echo "Creating preset $PRESET"
  echo "#!/bin/bash

export LLAMA_CUDA_VERSION='13.3.0-cudnn'
export LLAMA_BRANCH='$RELEASE_TAG'
export LLAMA_PRESET_NAME='$RELEASE_TAG-cuda-13.3.0-cudnn'
" > "$PRESET"
fi
