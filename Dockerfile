# Worker RunPod Serverless: CogVideoX-5B I2V + hậu kỳ YouTube (RealESRGAN x2, RIFE 24fps).
# Mọi model đóng sẵn vào image: cold start không tải gì, không cần Cached Models / Network Volume.
# Deploy: RunPod GitHub integration (Dockerfile ở gốc repo) hoặc ./docker/build.sh — xem docker/README.md.
# BUILD THỬ BƯỚC 3: như bước 2 (bỏ làm phẳng) và thay mọi `ADD <url>` bằng RUN tải model.
FROM runpod/worker-comfyui:5.10.0-base

# Worker chạy ComfyUI bằng /opt/venv; phải chỉ rõ --python, không thì uv cài vào
# /comfyui/.venv (có sẵn trong image gốc nhưng không dùng).
ENV UV_PYTHON=/opt/venv/bin/python

# Model tải bằng RUN + docker/fetch_models.py, KHÔNG dùng `ADD <url>`: build trên RunPod Hub fail
# ngay (không log) khi Dockerfile có ADD từ URL. File lớn, ít đổi: để đầu cho build sau dùng lại cache.
COPY docker/fetch_models.py /tmp/fetch_models.py

# CogVideoX-5B-I2V (~12GB): chỉ transformer, vae, scheduler — đúng phần CogVideoXWrapper đọc từ
# models/CogVideo/CogVideoX-5b-I2V (text encoder dùng T5 fp8 bên dưới). Ghim commit repo HF.
ARG COGVIDEOX_REPO=https://huggingface.co/zai-org/CogVideoX-5b-I2V/resolve/a6f0f4858a8395e7429d82493864ce92bf73af11
ARG COGVIDEOX_DIR=/comfyui/models/CogVideo/CogVideoX-5b-I2V
RUN $UV_PYTHON /tmp/fetch_models.py \
    ${COGVIDEOX_REPO}/transformer/diffusion_pytorch_model-00001-of-00003.safetensors ${COGVIDEOX_DIR}/transformer/diffusion_pytorch_model-00001-of-00003.safetensors \
    ${COGVIDEOX_REPO}/transformer/diffusion_pytorch_model-00002-of-00003.safetensors ${COGVIDEOX_DIR}/transformer/diffusion_pytorch_model-00002-of-00003.safetensors \
    ${COGVIDEOX_REPO}/transformer/diffusion_pytorch_model-00003-of-00003.safetensors ${COGVIDEOX_DIR}/transformer/diffusion_pytorch_model-00003-of-00003.safetensors \
    ${COGVIDEOX_REPO}/transformer/diffusion_pytorch_model.safetensors.index.json ${COGVIDEOX_DIR}/transformer/diffusion_pytorch_model.safetensors.index.json \
    ${COGVIDEOX_REPO}/transformer/config.json ${COGVIDEOX_DIR}/transformer/config.json \
    ${COGVIDEOX_REPO}/vae/diffusion_pytorch_model.safetensors ${COGVIDEOX_DIR}/vae/diffusion_pytorch_model.safetensors \
    ${COGVIDEOX_REPO}/vae/config.json ${COGVIDEOX_DIR}/vae/config.json \
    ${COGVIDEOX_REPO}/scheduler/scheduler_config.json ${COGVIDEOX_DIR}/scheduler/scheduler_config.json

# T5 fp8 thay cho text_encoder của repo CogVideoX: bản đó là dạng HF nhiều file mà CLIPLoader
# của ComfyUI không đọc được. Kèm RealESRGAN x2 cho hậu kỳ.
RUN $UV_PYTHON /tmp/fetch_models.py \
    https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors \
    /comfyui/models/text_encoders/t5xxl_fp8_e4m3fn.safetensors \
    https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.1/RealESRGAN_x2plus.pth \
    /comfyui/models/upscale_models/RealESRGAN_x2plus.pth

# Cùng commit ComfyUI đã chạy ổn ở local (0.37.0), thay cho 0.34.0 của image gốc.
ARG COMFYUI_COMMIT=912fca4f39b875a0360f2c5170568176ea813ded
RUN cd /comfyui \
 && git fetch --depth 1 origin ${COMFYUI_COMMIT} \
 && git checkout --force FETCH_HEAD \
 && uv pip install --python $UV_PYTHON -r requirements.txt

# Custom nodes, ghim commit.
ARG COGVIDEOX_WRAPPER_COMMIT=fdb8abd2790b5459ddc7066c31861bb0b62e988b
ARG FRAME_INTERPOLATION_COMMIT=26545cc2dd95bc3d27f056016300673bdeee78f5
RUN cd /comfyui/custom_nodes \
 && git clone https://github.com/kijai/ComfyUI-CogVideoXWrapper.git \
 && git -C ComfyUI-CogVideoXWrapper checkout ${COGVIDEOX_WRAPPER_COMMIT} \
 && git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git \
 && git -C ComfyUI-Frame-Interpolation checkout ${FRAME_INTERPOLATION_COMMIT} \
 && uv pip install --python $UV_PYTHON -r ComfyUI-CogVideoXWrapper/requirements.txt kornia scipy
# Frame-Interpolation: không cài cupy / opencv-contrib-python — RIFE không cần.
RUN $UV_PYTHON /tmp/fetch_models.py \
    https://github.com/Fannovel16/ComfyUI-Frame-Interpolation/releases/download/models/rife49.pth \
    /comfyui/custom_nodes/ComfyUI-Frame-Interpolation/ckpts/rife/rife49.pth

COPY nodes/free_memory_after_run.py /comfyui/custom_nodes/free_memory_after_run.py

# handler.py (repo) thay /handler.py gốc và import lại handler gốc.
RUN mv /handler.py /worker_comfyui_handler.py
COPY handler.py /handler.py

# /comfyui/.venv (8GB) của image gốc không được dùng (worker chạy /opt/venv); bỏ cả cache uv.
RUN rm -rf /comfyui/.venv /root/.cache /tmp/fetch_models.py
