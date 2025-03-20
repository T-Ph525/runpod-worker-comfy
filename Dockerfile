# Stage 1: Base image with common dependencies
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04 as base

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_PREFER_BINARY=1
ENV PYTHONUNBUFFERED=1 
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Install Python, git, wget, and other necessary tools
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    git \
    wget \
    libgl1 \
    && ln -sf /usr/bin/python3.10 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip

# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Install comfy-cli
RUN pip install comfy-cli

# Install ComfyUI
RUN /usr/bin/yes | comfy --workspace /comfyui install --cuda-version 11.8 --nvidia --version 0.3.26

# Change working directory to ComfyUI
WORKDIR /comfyui

# Install RunPod SDK and requests library
RUN pip install runpod requests

# Add support for network volume
ADD src/extra_model_paths.yaml ./

# Move back to root
WORKDIR /

# Add startup scripts
ADD src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json ./
RUN chmod +x /start.sh /restore_snapshot.sh

# Copy snapshot file if available
ADD *snapshot*.json / || true

# Restore snapshot to install custom nodes
RUN /restore_snapshot.sh

# Set default working directory
WORKDIR /comfyui

# Expose necessary ports (if needed)
EXPOSE 8188

# Set environment variables for GPU visibility
ENV CUDA_VISIBLE_DEVICES=0

# Start container using entrypoint for better compatibility
ENTRYPOINT ["/start.sh"]

# =======================
# Stage 2: Model Download
# =======================
FROM base as downloader

ARG HUGGINGFACE_ACCESS_TOKEN

# Ensure model directories exist
RUN mkdir -p /runpod-volume/models/checkpoints /runpod-volume/models/vae

# Download models from Hugging Face (if they are not already present)
RUN wget -nc -O /runpod-volume/models/checkpoints/uberRealisticPornMerge_urpmv13Inpainting.safetensors \
    https://huggingface.co/mrcuddle/urpm-inpaint-v13/resolve/main/uberRealisticPornMerge_urpmv13Inpainting.safetensors && \
    wget -nc -O /runpod-volume/models/checkpoints/uberRealisticPornMerge21_v2.safetensors \
    https://huggingface.co/mrcuddle/URPM-SD2.1/resolve/main/uberRealisticPornMerge21_v2.safetensors && \
    wget -nc -O /runpod-volume/models/vae/sdxl_vae.safetensors \
    https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors && \
    wget -nc -O /runpod-volume/models/vae/sdxl-vae-fp16-fix.safetensors \
    https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors

# ==========================
# Stage 3: Final Deployment
# ==========================
FROM base as final

# Copy models from the previous stage
COPY --from=downloader /runpod-volume/models /runpod-volume/models

# Ensure the working directory is set
WORKDIR /comfyui

# Start the container with the entrypoint
ENTRYPOINT ["/start.sh"]
