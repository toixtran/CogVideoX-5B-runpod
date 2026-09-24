#!/usr/bin/env bash
# Tải weights CogVideoX-5B cho ComfyUI (tối ưu cho GPU 12GB VRAM).
#
# Cách dùng:
#   ./scripts/download_models.sh          # I2V (mặc định, ~17GB)
#   ./scripts/download_models.sh t2v      # thêm T2V (+12GB)
#
# Đường dẫn khớp với ComfyUI-CogVideoXWrapper (node DownloadAndLoadCogVideoModel)
# nên node sẽ không tải lại lần nữa.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMFY="$ROOT/comfyui"
PY="$COMFY/.venv/bin/python"
MODELS="$COMFY/models"

want_t2v=false
for arg in "$@"; do
  case "$arg" in
    t2v) want_t2v=true ;;
    *) echo "Tham số không hợp lệ: $arg" >&2; exit 1 ;;
  esac
done

"$PY" - "$MODELS" "$want_t2v" <<'EOF'
import os, sys, shutil
from huggingface_hub import snapshot_download, hf_hub_download

models, want_t2v = sys.argv[1], sys.argv[2] == "true"
cog_patterns = ["*transformer*", "*scheduler*", "*vae*"]

jobs = [("THUDM/CogVideoX-5b-I2V", os.path.join(models, "CogVideo", "CogVideoX-5b-I2V"))]
if want_t2v:
    jobs.append(("THUDM/CogVideoX-5b", os.path.join(models, "CogVideo", "CogVideoX-5b")))

for repo, dest in jobs:
    print(f"==> {repo} -> {dest}", flush=True)
    snapshot_download(repo_id=repo, local_dir=dest, allow_patterns=cog_patterns)

te_dir = os.path.join(models, "text_encoders")
te_file = "t5xxl_fp8_e4m3fn.safetensors"
if not os.path.exists(os.path.join(te_dir, te_file)):
    print(f"==> T5-XXL fp8 -> {te_dir}", flush=True)
    hf_hub_download("comfyanonymous/flux_text_encoders", te_file, local_dir=te_dir)
    shutil.rmtree(os.path.join(te_dir, ".cache"), ignore_errors=True)

print("Xong.")
EOF

# Hậu kỳ cho template YouTube: upscale x2 (RealESRGAN) + nội suy khung hình (RIFE 4.9)
fetch() { [ -s "$2" ] || { mkdir -p "$(dirname "$2")"; echo "==> $(basename "$2")"; curl -fL --retry 3 -o "$2.part" "$1" && mv "$2.part" "$2"; }; }
fetch https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.1/RealESRGAN_x2plus.pth \
      "$MODELS/upscale_models/RealESRGAN_x2plus.pth"
fetch https://github.com/Fannovel16/ComfyUI-Frame-Interpolation/releases/download/models/rife49.pth \
      "$COMFY/custom_nodes/ComfyUI-Frame-Interpolation/ckpts/rife/rife49.pth"
