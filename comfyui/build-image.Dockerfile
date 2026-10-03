ARG BASE_PYTORCH_IMAGE="docker.io/pytorch/pytorch:2.13.0-cuda13.2-cudnn9-runtime"

ARG COMFY_REPO="https://github.com/Comfy-Org/ComfyUI.git"
ARG COMFY_BRANCH="master"
ARG COMFY_COMMIT=""
ARG SAGEATTENTION_REPO="https://github.com/thu-ml/SageAttention.git"
ARG SAGEATTENTION_REF="v2.2.0"
ARG CUDA_TOOLKIT_PACKAGE="cuda-toolkit-13-2"

############# Base image #############
FROM ${BASE_PYTORCH_IMAGE} AS torch_base
RUN python3 -m pip config set global.break-system-packages true && \
    apt-get update && apt-get install git curl wget jq aria2 python3-venv -y

############# Clone repos #############
FROM torch_base AS files_comfy
ARG COMFY_REPO
ARG COMFY_BRANCH
ARG COMFY_COMMIT
# Clone
WORKDIR /files/comfy
RUN git clone --depth 1 --recurse-submodules --shallow-submodules --jobs 4 --branch ${COMFY_BRANCH} ${COMFY_REPO} .
RUN if [ "$COMFY_COMMIT" != "" ]; then git checkout "$COMFY_COMMIT"; fi
COPY /entrypoint.sh /files/comfy

FROM files_comfy AS files_comfy_requirements
WORKDIR /files/comfy-requirements
RUN cp /files/comfy/requirements.txt /files/comfy/manager_requirements.txt .
RUN find .

############# Build SageAttention for Blackwell #############
FROM torch_base AS sageattention_builder
ARG SAGEATTENTION_REPO
ARG SAGEATTENTION_REF
ARG CUDA_TOOLKIT_PACKAGE
RUN curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb \
      -o /tmp/cuda-keyring.deb && \
    dpkg -i /tmp/cuda-keyring.deb && rm /tmp/cuda-keyring.deb && \
    apt-get update && \
    apt-get install -y --no-install-recommends build-essential ninja-build ${CUDA_TOOLKIT_PACKAGE} && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /files/sageattention
RUN git clone --depth 1 --branch ${SAGEATTENTION_REF} ${SAGEATTENTION_REPO} .
# SageAttention v2.2.0 hardcodes C++17, while PyTorch 2.14 headers require C++20.
RUN sed -i 's/-std=c++17/-std=c++20/g' setup.py sageattention3_blackwell/setup.py
# SageAttention defaults MAX_JOBS to 32, which can exhaust memory on hosted CI runners.
ENV TORCH_CUDA_ARCH_LIST="12.0" CUDA_HOME="/usr/local/cuda" MAX_JOBS="2" EXT_PARALLEL="1"
RUN python3 -m pip wheel --no-deps --no-build-isolation --wheel-dir /wheels .
WORKDIR /files/sageattention/sageattention3_blackwell
# SageAttention3's setup.py probes the local GPU; select sm120 without requiring a GPU on the builder.
# The CUDA driver stubs are needed to link its two extensions against libcuda.
RUN LIBRARY_PATH="/usr/local/cuda/lib64/stubs:/usr/local/cuda/targets/x86_64-linux/lib/stubs" \
    python3 -c 'import runpy, torch; torch.cuda.get_device_capability = lambda *_: (12, 0); runpy.run_path("setup.py", run_name="__main__")' \
    bdist_wheel --dist-dir /wheels

############# Copy and install all #############
FROM torch_base AS final
WORKDIR /comfyui
COPY --from=files_comfy_requirements /files/comfy-requirements /comfyui
# The PyTorch base includes spin (a development CLI), which requires click<8.4;
# huggingface_hub requires click>=8.4.2. Neither ComfyUI nor SageAttention needs spin.
RUN pip uninstall -y spin && \
    pip install huggingface_hub modelscope yq einops ninja -r requirements.txt -r manager_requirements.txt && \
    pip check
COPY --from=sageattention_builder /wheels /wheels
RUN pip install --no-deps /wheels/sageattention-*.whl /wheels/sageattn3-*.whl && rm -rf /wheels
COPY --from=files_comfy /files/comfy /comfyui
ENTRYPOINT ["/comfyui/entrypoint.sh"]
