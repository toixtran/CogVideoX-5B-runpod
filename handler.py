# Entrypoint RunPod của worker: dùng nguyên handler của worker-comfyui (Dockerfile đổi tên
# /handler.py gốc thành /worker_comfyui_handler.py và đặt file này vào /handler.py, nơi
# /start.sh gọi). File nằm trong repo để RunPod GitHub integration nhận ra handler.
#
# Mỗi output kèm key "metrics" (GPU, VRAM đỉnh, thời gian job, job đầu tiên của worker hay không,
# log load/offload model + s/it của ComfyUI)
# để so sánh GPU (scripts/benchmark_runpod.py). VRAM đo bằng nvidia-smi: tính cả phần ComfyUI
# cache/giữ lại, không chỉ tensor đang dùng.
import re
import subprocess
import threading
import time
from datetime import datetime

import requests
import runpod

from worker_comfyui_handler import COMFY_HOST, handler as comfy_handler

# Dòng log ComfyUI cho biết model nằm trọn trong VRAM hay bị đẩy một phần ra RAM, và tốc độ lấy mẫu.
LOAD_LOG = re.compile(r"Requested to load|loaded completely|loaded partially|Unloaded partially|"
                      r"Prompt executed|\d+/\d+ \[[\d:]+<[\d:?]+, +[\d.]+(s/it|it/s)\]")

WORKER_STARTED = time.time()
_jobs_done = 0


def _gpu_query():
    """(tên GPU, VRAM tổng MiB, VRAM đang dùng MiB) của GPU 0, hoặc None nếu không đọc được."""
    try:
        out = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,memory.total,memory.used", "--format=csv,noheader,nounits", "-i", "0"],
            capture_output=True, text=True, timeout=5,
        ).stdout.strip()
        name, total, used = [s.strip() for s in out.split(",")]
        return name, int(total), int(used)
    except Exception:
        return None


def _comfy_log_since(since_iso):
    """Các dòng log ComfyUI (LOAD_LOG) ghi từ since_iso, lấy qua /internal/logs/raw."""
    try:
        entries = requests.get(f"http://{COMFY_HOST}/internal/logs/raw", timeout=5).json()["entries"]
    except Exception:
        return None
    text = "".join(e["m"] for e in entries if e["t"] >= since_iso)
    lines = [l.strip() for l in re.split(r"[\r\n]+", text)]
    return [l for l in lines if LOAD_LOG.search(l)][-60:]


def handler(job):
    global _jobs_done
    since_iso = datetime.now().isoformat()
    first = _gpu_query()
    peak = [first[2] if first else 0]
    stop = threading.Event()

    def sample():
        while not stop.wait(0.5):
            q = _gpu_query()
            if q:
                peak[0] = max(peak[0], q[2])

    sampler = threading.Thread(target=sample, daemon=True)
    sampler.start()
    started = time.time()
    try:
        result = comfy_handler(job)
    finally:
        stop.set()
        sampler.join(timeout=2)
    elapsed = time.time() - started
    _jobs_done += 1
    if isinstance(result, dict):
        result["metrics"] = {
            "gpu": first[0] if first else None,
            "vram_total_mib": first[1] if first else None,
            "vram_peak_mib": peak[0],
            "job_seconds": round(elapsed, 2),
            "worker_job_index": _jobs_done,  # 1 = job đầu tiên: có thời gian load model
            "worker_uptime_s": round(started - WORKER_STARTED, 1),
            "comfy_log": _comfy_log_since(since_iso),
        }
    return result


if __name__ == "__main__":
    print("comfyui-video-runpod - Starting handler...")
    runpod.serverless.start({"handler": handler})
