# Worker RunPod Serverless: CogVideoX-5B I2V + hậu kỳ YouTube (RealESRGAN x2, RIFE 24fps).
# Image chỉ có phần mềm; mọi model (~17GB) nằm trong 1 repo HF dùng làm RunPod Cached Model
# (ô "Model" của endpoint: toixtran/cogvideox-5b-i2v-comfy, tạo bằng scripts/publish_models_hf.sh).
# docker/start.sh symlink model từ cache vào ComfyUI. Build RunPod Hub fail (không log) khi có model trong image.
# Deploy: RunPod GitHub integration / Hub (Dockerfile ở gốc repo) hoặc ./docker/build.sh — xem docker/README.md.
FROM runpod/worker-comfyui:5.10.0-base

# Worker chạy ComfyUI bằng /opt/venv; phải chỉ rõ --python, không thì uv cài vào
# /comfyui/.venv (có sẵn trong image gốc nhưng không dùng).
ENV UV_PYTHON=/opt/venv/bin/python

# THỬ (nhánh bisect): bỏ bước cập nhật ComfyUI 0.34 -> 0.37 để xem nó có làm build RunPod
# fail không. v1.0.1 (chỉ FROM + thay handler) build được; v1.0.4 (thêm bước này + custom
# nodes + copy) fail. Không dùng nhánh này cho production.

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

COPY nodes/free_memory_after_run.py /comfyui/custom_nodes/free_memory_after_run.py

# handler.py (repo) thay /handler.py gốc và import lại handler gốc.
RUN mv /handler.py /worker_comfyui_handler.py
COPY handler.py /handler.py

COPY docker/start.sh /start-cogvideox.sh
RUN chmod 755 /start-cogvideox.sh

# /comfyui/.venv (8GB) của image gốc không được dùng (worker chạy /opt/venv); bỏ cả cache uv.
RUN rm -rf /comfyui/.venv /root/.cache

CMD ["/start-cogvideox.sh"]
