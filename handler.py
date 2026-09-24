# Entrypoint RunPod của worker: dùng nguyên handler của worker-comfyui (Dockerfile đổi tên
# /handler.py gốc thành /worker_comfyui_handler.py và đặt file này vào /handler.py, nơi
# /start.sh gọi). File nằm trong repo để RunPod GitHub integration nhận ra handler.
import runpod

from worker_comfyui_handler import handler

if __name__ == "__main__":
    print("cogvideox-5b-runpod - Starting handler...")
    runpod.serverless.start({"handler": handler})
