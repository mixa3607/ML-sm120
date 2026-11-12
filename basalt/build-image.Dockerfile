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
# Fetch the requested commit directly so pins outside the shallow branch work too.
RUN git init . && \
    git remote add origin "${BASALT_REPO}" && \
    git fetch --depth 1 origin "${BASALT_COMMIT:-${BASALT_BRANCH}}" && \
    git checkout --detach FETCH_HEAD && \
    git rev-parse HEAD | tee REVISION

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

############# Runtime #############
FROM ${RUNTIME_CUDA_IMAGE} AS final
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates python3 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/basalt
# Keep the upstream install layout: the engine locates Python and data beside bin/.
COPY --from=builder /opt/basalt/.venv /opt/basalt/.venv
COPY --from=builder /opt/basalt/bin /opt/basalt/bin
COPY --from=builder /opt/basalt/serve /opt/basalt/serve
COPY --from=builder /opt/basalt/tools /opt/basalt/tools
COPY --from=builder /opt/basalt/data /opt/basalt/data
COPY --from=builder /opt/basalt/requirements.txt /opt/basalt/REVISION /opt/basalt/LICENSE /opt/basalt/THIRD_PARTY_LICENSES /opt/basalt/

ENV HOME=/data PYTHONUNBUFFERED=1 PATH=/opt/basalt/bin:$PATH
EXPOSE 8080
ENTRYPOINT ["basalt", "serve", "--config", "/data/basalt_config.json", "--host", "0.0.0.0"]
