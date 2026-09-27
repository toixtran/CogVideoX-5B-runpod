#!/usr/bin/env bash
# Trỏ model từ RunPod Cached Models vào chỗ ComfyUI / custom node tìm, rồi chạy /start.sh gốc
# của worker-comfyui. Ô "Model" của endpoint = MODEL_REPO (repo HF gom sẵn model);
# RunPod tải sẵn trước khi worker chạy nên cold start không tải gì.
#
# Repo xếp theo thư mục models của ComfyUI (diffusion_models/, text_encoders/, vae/, loras/,
# upscale_models/...): mỗi file được link vào /comfyui/models/<thư mục>/. Ngoại lệ của CogVideoX:
#   CogVideoX-5b-I2V/ -> models/CogVideo/CogVideoX-5b-I2V (CogVideoXWrapper đọc cả thư mục)
#   rife/             -> custom_nodes/ComfyUI-Frame-Interpolation/ckpts/rife/
MODEL_REPO="${MODEL_REPO:-toixtran/cogvideox-5b-i2v-comfy}"

# Cờ thêm cho ComfyUI (/start.sh gốc đã được Dockerfile chèn $COMFY_EXTRA_ARGS). Đặt biến
# COMFY_EXTRA_ARGS trên endpoint để ghi đè; đặt rỗng để tắt SageAttention.
export COMFY_EXTRA_ARGS="${COMFY_EXTRA_ARGS---use-sage-attention}"
# Hook giải phóng VRAM sau mỗi job chỉ cần cho CogVideoXWrapper; model native (MiniMax-H3) giữ
# lại trong RAM để job kế tiếp trên cùng worker khỏi load lại (~11s).
case "$MODEL_REPO" in
  *cogvideox*) export FREE_MEMORY_AFTER_RUN="${FREE_MEMORY_AFTER_RUN:-1}" ;;
  *)           export FREE_MEMORY_AFTER_RUN="${FREE_MEMORY_AFTER_RUN:-0}" ;;
esac
CACHE="/runpod-volume/huggingface-cache/hub/models--${MODEL_REPO//\//--}"

SNAPSHOT="$CACHE/snapshots/$(cat "$CACHE/refs/main" 2>/dev/null)"
[ -d "$SNAPSHOT" ] && [ -f "$CACHE/refs/main" ] || SNAPSHOT="$(ls -d "$CACHE"/snapshots/*/ 2>/dev/null | head -1)"
SNAPSHOT="${SNAPSHOT%/}"

if [ -z "$SNAPSHOT" ] || [ ! -d "$SNAPSHOT" ]; then
  echo "comfyui-video-runpod: ERROR không thấy cached model $MODEL_REPO ($CACHE) — điền ô Model của endpoint = $MODEL_REPO (repo private thì thêm HF token). Job sẽ lỗi thiếu model." >&2
  exec /start.sh
fi

link() { mkdir -p "$(dirname "$2")" && ln -sfn "$1" "$2"; }
for dir in "$SNAPSHOT"/*/; do
  name="$(basename "$dir")"
  case "$name" in
    CogVideoX-5b-I2V) link "${dir%/}" /comfyui/models/CogVideo/CogVideoX-5b-I2V ;;
    rife) for f in "$dir"*; do link "$f" "/comfyui/custom_nodes/ComfyUI-Frame-Interpolation/ckpts/rife/$(basename "$f")"; done ;;
    licenses) ;;
    *) for f in "$dir"*; do link "$f" "/comfyui/models/$name/$(basename "$f")"; done ;;
  esac
done
echo "comfyui-video-runpod: model từ cached model $SNAPSHOT"

exec /start.sh
