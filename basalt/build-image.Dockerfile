# syntax=docker/dockerfile:1
ARG BASE_CUDA_IMAGE="docker.io/nvidia/cuda:13.4.3-devel-ubuntu24.04"
ARG RUNTIME_CUDA_IMAGE="docker.io/nvidia/cuda:13.4.3-runtime-ubuntu24.04"

############# Prepare code and build #############
FROM ${BASE_CUDA_IMAGE} AS builder
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential ca-certificates ccache cmake git python3 python3-venv && \
    rm -rf /var/lib/apt/lists/*

ARG BASALT_REPO="https://github.com/jesdga95/basalt.git"
ARG BASALT_BRANCH="v0.3.2"
ARG BASALT_COMMIT=""
WORKDIR /opt/basalt
RUN git clone --depth 1 --recurse-submodules --shallow-submodules --jobs 4 --branch "${BASALT_BRANCH}" "${BASALT_REPO}" .
RUN if [ "$BASALT_COMMIT" != "" ]; then git checkout "$BASALT_COMMIT"; fi
RUN git rev-parse HEAD | tee REVISION

ARG CUDA_ARCH="120"
ARG BUILD_JOBS="4"
ARG CCACHE_MAXSIZE="2G"
ENV CCACHE_DIR=/ccache CCACHE_MAXSIZE=${CCACHE_MAXSIZE}
RUN --mount=type=cache,target=/ccache \
    cmake -S . -B build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCH}" \
      -DCMAKE_C_COMPILER_LAUNCHER=ccache \
      -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
      -DCMAKE_CUDA_COMPILER_LAUNCHER=ccache \
      -DBUILD_TESTING=OFF && \
    cmake --build build --parallel "${BUILD_JOBS}"
RUN python3 -m venv .venv && \
    .venv/bin/pip install --no-cache-dir -r requirements.txt && \
    .venv/bin/pip check
# Keep only the runtime tree, without sources, Git metadata, or build intermediates.
RUN mkdir /runtime && \
    mv .venv bin serve tools data requirements.txt REVISION LICENSE THIRD_PARTY_LICENSES /runtime/

############# Runtime #############
FROM ${RUNTIME_CUDA_IMAGE} AS final
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates python3 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/basalt
# Keep the upstream install layout: the engine locates Python and data beside bin/.
COPY --from=builder /runtime/ /opt/basalt/

ENV HOME=/data PYTHONUNBUFFERED=1 PATH=/opt/basalt/bin:$PATH
EXPOSE 8080
ENTRYPOINT ["basalt", "serve", "--config", "/data/basalt_config.json", "--host", "0.0.0.0"]
