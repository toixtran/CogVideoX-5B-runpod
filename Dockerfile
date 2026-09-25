# BẢN BUILD THỬ TỐI THIỂU: chỉ kiểm tra RunPod Hub có build được trên image gốc worker-comfyui không.
# Chưa có custom node / model nên test của Hub sẽ fail — chỉ xem bước build có qua không.
# Bản đầy đủ: git show b946d79:Dockerfile
FROM runpod/worker-comfyui:5.10.0-base

# handler.py (repo) thay /handler.py gốc và import lại handler gốc.
RUN mv /handler.py /worker_comfyui_handler.py
COPY handler.py /handler.py
