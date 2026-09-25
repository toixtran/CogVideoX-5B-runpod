#!/usr/bin/env bash
# Gom mọi model worker cần vào 1 repo Hugging Face, để endpoint RunPod dùng làm Cached Model
# (mỗi endpoint chỉ cache được 1 repo). Chạy 1 lần; chạy lại thì bỏ qua file đã tải/đã upload.
#
#   export HF_TOKEN=hf_...                        # token quyền write: https://huggingface.co/settings/tokens
#   ./scripts/publish_models_hf.sh                # -> toixtran/cogvideox-5b-i2v-comfy (private)
#   HF_REPO=<user>/<tên> PRIVATE=false ./scripts/publish_models_hf.sh
#
# Cần ~18GB đĩa trống, curl, python3. Upload ~17GB: nên chạy trên Pod RunPod (mạng nhanh) —
# xem docker/README.md. Thư mục tải về (hf-models/) cũng dùng được cho docker/test_local.sh.
#
# Cấu trúc repo — docker/start.sh symlink đúng các đường dẫn này vào ComfyUI:
#   CogVideoX-5b-I2V/{transformer,vae,scheduler}/...   -> models/CogVideo/CogVideoX-5b-I2V
#   text_encoders/t5xxl_fp8_e4m3fn.safetensors          -> models/text_encoders/
#   upscale_models/RealESRGAN_x2plus.pth                -> models/upscale_models/
#   rife/rife49.pth                                     -> custom_nodes/ComfyUI-Frame-Interpolation/ckpts/rife/
set -euo pipefail

HF_REPO="${HF_REPO:-toixtran/cogvideox-5b-i2v-comfy}"
PRIVATE="${PRIVATE:-true}"
DIR="${DIR:-$(cd "$(dirname "$0")/.." && pwd)/hf-models}"
: "${HF_TOKEN:?Đặt HF_TOKEN (token quyền write) trước khi chạy}"

# Cùng commit repo CogVideoX với bản đã test.
COGVIDEOX=https://huggingface.co/zai-org/CogVideoX-5b-I2V/resolve/a6f0f4858a8395e7429d82493864ce92bf73af11

# fetch <url> <đường dẫn trong repo>: bỏ qua nếu đã có, tải tiếp nếu dở, thử lại khi lỗi mạng.
fetch() {
  local dst="$DIR/$2"
  [ -s "$dst" ] && { echo "đã có  $2"; return; }
  mkdir -p "$(dirname "$dst")"
  echo "tải    $2"
  curl -fL --retry 5 --retry-delay 10 -C - -o "$dst.part" "$1"
  mv "$dst.part" "$dst"
}

for f in transformer/diffusion_pytorch_model-00001-of-00003.safetensors \
         transformer/diffusion_pytorch_model-00002-of-00003.safetensors \
         transformer/diffusion_pytorch_model-00003-of-00003.safetensors \
         transformer/diffusion_pytorch_model.safetensors.index.json \
         transformer/config.json \
         vae/diffusion_pytorch_model.safetensors \
         vae/config.json \
         scheduler/scheduler_config.json; do
  fetch "$COGVIDEOX/$f" "CogVideoX-5b-I2V/$f"
done
fetch https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors \
  text_encoders/t5xxl_fp8_e4m3fn.safetensors
fetch https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.1/RealESRGAN_x2plus.pth \
  upscale_models/RealESRGAN_x2plus.pth
fetch https://github.com/Fannovel16/ComfyUI-Frame-Interpolation/releases/download/models/rife49.pth \
  rife/rife49.pth

# License gốc đi kèm khi phân phối lại.
fetch "$COGVIDEOX/LICENSE" licenses/CogVideoX-LICENSE
fetch https://raw.githubusercontent.com/xinntao/Real-ESRGAN/master/LICENSE licenses/Real-ESRGAN-LICENSE
fetch https://raw.githubusercontent.com/hzwer/Practical-RIFE/main/LICENSE licenses/RIFE-LICENSE

cat > "$DIR/README.md" <<EOF
---
license: other
license_name: cogvideox-license
license_link: https://huggingface.co/zai-org/CogVideoX-5b-I2V/blob/main/LICENSE
---
# CogVideoX-5B I2V — model cho ComfyUI worker RunPod

Gom sẵn mọi model để dùng làm **Cached Model** của endpoint RunPod Serverless
(\`toixtran/CogVideoX-5B-runpod\`). Không chỉnh sửa trọng số; chỉ phân phối lại.

| Đường dẫn | Nguồn | License |
|---|---|---|
| \`CogVideoX-5b-I2V/\` (transformer, vae, scheduler) | [zai-org/CogVideoX-5b-I2V](https://huggingface.co/zai-org/CogVideoX-5b-I2V) @ a6f0f48 | CogVideoX License — \`licenses/CogVideoX-LICENSE\` |
| \`text_encoders/t5xxl_fp8_e4m3fn.safetensors\` | [comfyanonymous/flux_text_encoders](https://huggingface.co/comfyanonymous/flux_text_encoders) (Google T5 v1.1 XXL) | Apache-2.0 |
| \`upscale_models/RealESRGAN_x2plus.pth\` | [xinntao/Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) v0.2.1 | BSD-3-Clause — \`licenses/Real-ESRGAN-LICENSE\` |
| \`rife/rife49.pth\` | [hzwer/Practical-RIFE](https://github.com/hzwer/Practical-RIFE) qua ComfyUI-Frame-Interpolation | MIT — \`licenses/RIFE-LICENSE\` |
EOF

echo "upload $DIR -> $HF_REPO (private=$PRIVATE)"
# venv riêng (ngoài thư mục upload): python hệ thống (vd. Homebrew) thường chặn pip install.
VENV="$DIR/../.hf-venv"
[ -x "$VENV/bin/python" ] || python3 -m venv "$VENV"
"$VENV/bin/python" -m pip install -q -U "huggingface_hub[hf_xet]>=2.0"
HF_REPO="$HF_REPO" PRIVATE="$PRIVATE" DIR="$DIR" "$VENV/bin/python" - <<'EOF'
import os
from huggingface_hub import HfApi

api = HfApi()
repo, folder = os.environ["HF_REPO"], os.environ["DIR"]
api.create_repo(repo, repo_type="model", private=os.environ["PRIVATE"] == "true", exist_ok=True)
# huggingface_hub 2.0 bỏ upload_large_folder: upload_folder tự chia nhiều commit với thư mục
# lớn, bị ngắt thì chạy lại script là upload tiếp (file đã commit được bỏ qua).
api.upload_folder(repo_id=repo, folder_path=folder, repo_type="model",
                  ignore_patterns=["**/*.part", ".cache/**"])
print(f"xong: https://huggingface.co/{repo}")
EOF
