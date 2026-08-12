ARG CUDA_BASE_IMAGE=nvidia/cuda:12.8.1-base-ubuntu22.04
FROM ${CUDA_BASE_IMAGE}

ARG COMFYUI_REF=v0.31.0
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential ca-certificates cmake git python3 python3-dev \
       python3-pip python3-venv ffmpeg libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone --depth 1 --branch "${COMFYUI_REF}" \
    https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI

WORKDIR /opt/ComfyUI
RUN python3 -m venv "${VIRTUAL_ENV}" \
    && python3 -m pip install --upgrade pip setuptools wheel \
    && python3 -m pip install \
      torch torchvision torchaudio \
      --index-url https://download.pytorch.org/whl/cu128 \
    && python3 -m pip install -r requirements.txt

COPY docker/entrypoint.sh /usr/local/bin/comfyui-entrypoint
COPY config/custom-nodes.lock /opt/config/custom-nodes.lock
COPY scripts/install-custom-nodes.sh /usr/local/bin/install-custom-nodes
RUN chmod +x /usr/local/bin/comfyui-entrypoint \
    && chmod +x /usr/local/bin/install-custom-nodes \
    && CUSTOM_NODES_DIR=/opt/ComfyUI/custom_nodes \
       CUSTOM_NODES_LOCK=/opt/config/custom-nodes.lock \
       /usr/local/bin/install-custom-nodes \
    && find /opt/ComfyUI/custom_nodes -mindepth 2 -maxdepth 2 \
       -name requirements.txt -print0 \
       | while IFS= read -r -d '' requirements; do \
           python3 -m pip install -r "${requirements}"; \
         done \
    && mkdir -p /data/models /data/input /data/output /data/temp /data/user

EXPOSE 8188
ENTRYPOINT ["comfyui-entrypoint"]
