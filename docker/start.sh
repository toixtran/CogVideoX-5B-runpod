#!/usr/bin/env bash
# Trỏ model từ RunPod Cached Models vào chỗ ComfyUI / custom node tìm, rồi chạy /start.sh gốc
# của worker-comfyui. Ô "Model" của endpoint = MODEL_REPO (repo gom sẵn bởi
# scripts/publish_models_hf.sh); RunPod tải sẵn trước khi worker chạy nên cold start không tải gì.
MODEL_REPO="${MODEL_REPO:-toixtran/cogvideox-5b-i2v-comfy}"
CACHE="/runpod-volume/huggingface-cache/hub/models--${MODEL_REPO//\//--}"

SNAPSHOT="$CACHE/snapshots/$(cat "$CACHE/refs/main" 2>/dev/null)"
[ -f "$SNAPSHOT/CogVideoX-5b-I2V/transformer/config.json" ] \
  || SNAPSHOT="$(ls -d "$CACHE"/snapshots/*/ 2>/dev/null | head -1)"
SNAPSHOT="${SNAPSHOT%/}"

if [ ! -f "$SNAPSHOT/CogVideoX-5b-I2V/transformer/config.json" ]; then
  echo "cogvideox-5b-runpod: ERROR không thấy cached model $MODEL_REPO ($CACHE) — điền ô Model của endpoint = $MODEL_REPO (repo private thì thêm HF token). Job sẽ lỗi thiếu model." >&2
  exec /start.sh
fi

link() { mkdir -p "$(dirname "$2")" && ln -sfn "$SNAPSHOT/$1" "$2"; }
link CogVideoX-5b-I2V                            /comfyui/models/CogVideo/CogVideoX-5b-I2V
link text_encoders/t5xxl_fp8_e4m3fn.safetensors  /comfyui/models/text_encoders/t5xxl_fp8_e4m3fn.safetensors
link upscale_models/RealESRGAN_x2plus.pth        /comfyui/models/upscale_models/RealESRGAN_x2plus.pth
link rife/rife49.pth                             /comfyui/custom_nodes/ComfyUI-Frame-Interpolation/ckpts/rife/rife49.pth
echo "cogvideox-5b-runpod: model từ cached model $SNAPSHOT"

exec /start.sh
