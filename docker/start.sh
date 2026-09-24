#!/usr/bin/env bash
# Trỏ CogVideoX từ RunPod Cached Models (ô "Model" của endpoint = THUDM/CogVideoX-5b-I2V)
# vào chỗ CogVideoXWrapper tìm model, rồi chạy /start.sh gốc của worker-comfyui.
CACHE=/runpod-volume/huggingface-cache/hub/models--THUDM--CogVideoX-5b-I2V
TARGET=/comfyui/models/CogVideo/CogVideoX-5b-I2V

SNAPSHOT="$CACHE/snapshots/$(cat "$CACHE/refs/main" 2>/dev/null)"
[ -f "$SNAPSHOT/transformer/config.json" ] || SNAPSHOT="$(ls -d "$CACHE"/snapshots/*/ 2>/dev/null | head -1)"

if [ -f "${SNAPSHOT%/}/transformer/config.json" ]; then
  ln -sfn "${SNAPSHOT%/}" "$TARGET"
  echo "cogvideox-5b-runpod: CogVideoX từ cached model $SNAPSHOT"
else
  echo "cogvideox-5b-runpod: WARNING không thấy cached model ($CACHE) — CogVideoXWrapper sẽ tự tải ~12GB từ HuggingFace mỗi lần cold start. Kiểm tra ô Model của endpoint." >&2
fi

exec /start.sh
