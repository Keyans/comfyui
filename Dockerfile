ARG CUDA_BASE_IMAGE=nvidia/cuda:12.8.1-base-ubuntu22.04
FROM ${CUDA_BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential ca-certificates cmake git python3 python3-dev \
       python3-pip python3-venv ffmpeg libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

ENV VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH

WORKDIR /opt
COPY vendor/ComfyUI /opt/ComfyUI
COPY vendor/custom_nodes /opt/ComfyUI/custom_nodes

WORKDIR /opt/ComfyUI
RUN python3 -m venv "${VIRTUAL_ENV}" \
    && python3 -m pip install --upgrade pip setuptools wheel \
    && python3 -m pip install \
      torch torchvision torchaudio \
      --index-url https://download.pytorch.org/whl/cu128 \
    && python3 -m pip install -r requirements.txt

COPY docker/entrypoint.sh /usr/local/bin/comfyui-entrypoint
RUN chmod +x /usr/local/bin/comfyui-entrypoint \
    && python3 -m pip install -r /opt/ComfyUI/manager_requirements.txt \
    && find /opt/ComfyUI/custom_nodes -mindepth 2 -maxdepth 2 \
       -name requirements.txt \
       -exec sh -c \
         'sed "\|^git+https://github.com/facebookresearch/sam2$|d" "$1" > /tmp/node-requirements.txt \
          && python3 -m pip install -r /tmp/node-requirements.txt' _ '{}' \; \
    && rm -f /tmp/node-requirements.txt \
    && mkdir -p /data/models /data/input /data/output /data/temp /data/user

EXPOSE 8188
ENTRYPOINT ["comfyui-entrypoint"]
