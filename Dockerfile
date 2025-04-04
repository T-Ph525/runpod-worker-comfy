# Stage 1: Base image with common dependencies
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04 as base

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1 
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Install Python, git and other necessary tools
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
RUN /usr/bin/yes | comfy --workspace /comfyui install --cuda-version 11.8 --nvidia

# Change working directory to ComfyUI
WORKDIR /comfyui
RUN comfy node install ComfyUI-ReActor Comfyui-Easy-Use IOHelpers
# Install runpod
RUN pip install runpod requests

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Go back to the root
WORKDIR /

# Add scripts
ADD src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json ./
RUN chmod +x /start.sh /restore_snapshot.sh

# Optionally copy the snapshot file
ADD *snapshot*.json /

# Restore the snapshot to install custom nodes
RUN /restore_snapshot.sh

# Start container
CMD ["/start.sh"]

# Stage 2: Download models
FROM base as downloader

ARG HUGGINGFACE_ACCESS_TOKEN
ARG MODEL_TYPE

# Change working directory to ComfyUI
WORKDIR /comfyui

# Create necessary directories
RUN mkdir -p models/checkpoints models/vae

# Ensure model directories exist
RUN mkdir -p models/checkpoints models/vae models/insightface models/facerestore_models models/facedetection

# Download models if not already present
RUN wget -nc -O models/checkpoints/URPM-Inpaint-SDXL.safetensors \
    https://huggingface.co/mrcuddle/URPM-Inpaint-Hyper-SDXL/resolve/main/URPM-Inpaint-SDXL.safetensors

RUN wget -nc -O models/vae/sdxl_vae.safetensors \
    https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors

RUN wget -nc -O models/vae/sdxl-vae-fp16-fix.safetensors \
    https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors

# Download Face Swapping & Face Restoration models
RUN wget -nc -O models/insightface/inswapper_128.onnx \
    https://huggingface.co/thebiglaskowski/inswapper_128.onnx/resolve/main/inswapper_128.onnx

RUN wget -nc -O models/facerestore_models/GFPGANv1.4.pth \
    https://huggingface.co/th2w33knd/GFPGANv1.4/resolve/main/GFPGANv1.4.pth

RUN wget -nc -O models/facedetection/detection_Resnet50_Final.pth \
    https://huggingface.co/krnl/detection_Resnet50_Final/resolve/main/detection_Resnet50_Final.pth


# Stage 3: Final image
FROM base as final

# Copy models from stage 2 to the final image
COPY --from=downloader /comfyui/models /comfyui/models

# Start container
CMD ["/start.sh"]
