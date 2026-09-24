#!/usr/bin/env bash
# Chạy image worker trên máy local, giả lập RunPod: CogVideoX local mount vào đúng chỗ
# Cached Models của RunPod; handler mở API ở http://localhost:8000 (/run, /status/{id}).
#
#   ./docker/test_local.sh                      # chạy nền, container tên cogvideox-worker
#   docker logs -f cogvideox-worker              # xem log
#   python3 scripts/runpod_client.py --url http://localhost:8000 \
#       --workflow workflows/api/cogvideox_youtube_16x9_local.json --image anh.jpg --prompt "..."
#   docker rm -f cogvideox-worker                # tắt
#
# Tắt ComfyUI local trước (pkill -f "python main.py"): GPU 12GB/RAM 31GB không đủ cho hai bản.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${IMAGE:-toitx/cogvideox-5b-runpod}:${TAG:-0.1.0}"

docker rm -f cogvideox-worker >/dev/null 2>&1 || true
docker run -d --name cogvideox-worker --gpus all -p 8000:8000 \
  -e SERVE_API_LOCALLY=true -e COMFY_LOG_LEVEL=INFO \
  -v "$ROOT/comfyui/models/CogVideo/CogVideoX-5b-I2V:/runpod-volume/huggingface-cache/hub/models--THUDM--CogVideoX-5b-I2V/snapshots/local:ro" \
  "$IMAGE"
echo "Đang khởi động $IMAGE — docker logs -f cogvideox-worker"
