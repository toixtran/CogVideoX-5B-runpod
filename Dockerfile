# Worker RunPod Serverless: CogVideoX-5B I2V + hậu kỳ YouTube (RealESRGAN x2, RIFE 24fps).
# CogVideoX (12GB) lấy từ RunPod Cached Models — ô "Model" của endpoint: THUDM/CogVideoX-5b-I2V.
# Deploy: RunPod GitHub integration (Dockerfile ở gốc repo) hoặc ./docker/build.sh — xem docker/README.md.
FROM runpod/worker-comfyui:5.10.0-base

# File lớn, ít đổi: để đầu cho build sau dùng lại cache.
# T5 fp8 đóng vào image: Cached Models chỉ giữ 1 repo/endpoint, và T5 trong repo THUDM là
# dạng HF nhiều file mà CLIPLoader của ComfyUI không đọc được.
ADD https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors \
    /comfyui/models/text_encoders/t5xxl_fp8_e4m3fn.safetensors
ADD https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.1/RealESRGAN_x2plus.pth \
    /comfyui/models/upscale_models/RealESRGAN_x2plus.pth

# Worker chạy ComfyUI bằng /opt/venv; phải chỉ rõ --python, không thì uv cài vào
# /comfyui/.venv (có sẵn trong image gốc nhưng không dùng).
ENV UV_PYTHON=/opt/venv/bin/python

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
ADD https://github.com/Fannovel16/ComfyUI-Frame-Interpolation/releases/download/models/rife49.pth \
    /comfyui/custom_nodes/ComfyUI-Frame-Interpolation/ckpts/rife/rife49.pth

COPY nodes/free_memory_after_run.py /comfyui/custom_nodes/free_memory_after_run.py

# handler.py (repo) thay /handler.py gốc và import lại handler gốc.
RUN mv /handler.py /worker_comfyui_handler.py
COPY handler.py /handler.py

# start.sh symlink cached model -> models/CogVideo/CogVideoX-5b-I2V rồi chạy /start.sh gốc.
RUN mkdir -p /comfyui/models/CogVideo
COPY --chmod=755 docker/start.sh /start-cogvideox.sh
CMD ["/start-cogvideox.sh"]
