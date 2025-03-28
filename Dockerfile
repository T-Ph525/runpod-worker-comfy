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

# Ensure model directories exist
RUN mkdir -p models/checkpoints models/vae models/insightface models/facerestore_models models/facedetection

# Download models from Hugging Face (if they are not already present)
RUN wget -nc -O models/checkpoints/URPM-Inpaint-SDXL.safetensors \
    https://huggingface.co/mrcuddle/URPM-Inpaint-Hyper-SDXL/resolve/main/URPM-Inpaint-SDXL.safetensors
    
RUN wget -nc -O models/vae/sdxl_vae.safetensors \
    https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors
    
RUN wget -nc -O models/vae/sdxl-vae-fp16-fix.safetensors \
    https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors

# Add commands to download inswapper_128.onnx and GFPGANv1.4.pth
RUN wget -nc -O models/insightface/inswapper_128.onnx \
    https://huggingface.co/thebiglaskowski/inswapper_128.onnx/resolve/main/inswapper_128.onnx

RUN wget -nc -O models/facerestore_models/GFPGANv1.4.pth \
    https://huggingface.co/th2w33knd/GFPGANv1.4/resolve/main/GFPGANv1.4.pth

RUN wget -nc -O models/facedetection/detection_Resnet50_Final.pth \
https://huggingface.co/krnl/detection_Resnet50_Final/resolve/main/detection_Resnet50_Final.pth

# ==========================
# Stage 3: Final Deployment
# ==========================
FROM base as final

# Ensure the working directory is set
WORKDIR /comfyui

# Start the container with the entrypoint
ENTRYPOINT ["/start.sh"]
