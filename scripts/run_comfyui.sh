#!/usr/bin/env bash
# Khởi động ComfyUI cho RTX 4070 Super (12GB VRAM).
#
# Mặc định KHÔNG dùng --highvram: ở ComfyUI hiện tại cờ này tắt "dynamic VRAM"
# và ép giữ mọi model trong GPU -> dễ OOM với model video trên 12GB.
#
#   ./scripts/run_comfyui.sh               # khuyến nghị
#   ./scripts/run_comfyui.sh --highvram    # đúng theo tài liệu gốc (có thể OOM)
#   ./scripts/run_comfyui.sh --lowvram     # nếu vẫn thiếu VRAM
#   LISTEN=0.0.0.0 ./scripts/run_comfyui.sh   # mở cho máy khác trong LAN
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/comfyui"

# Máy < 48GB RAM: mặc định ComfyUI ghim tới ~75% RAM và giữ cache đến khi RAM gần đầy; cộng với
# CogVideoXWrapper load transformer bf16 (~11GB) ngoài tầm quản lý của ComfyUI -> Linux OOM-kill
# ComfyUI ("Failed to fetch") trên máy 31GB. Từ 48GB trở lên giữ pinned memory: model lớn hơn
# VRAM (MiniMax-H3) chuyển RAM -> GPU nhanh hơn nhiều.
RAM_GB=$(awk '/MemTotal/ {print int($2 / 1048576)}' /proc/meminfo)
LOW_RAM_ARGS=()
[ "$RAM_GB" -lt 48 ] && LOW_RAM_ARGS=(--disable-pinned-memory --cache-none)

exec .venv/bin/python main.py \
  --listen "${LISTEN:-127.0.0.1}" \
  --port "${PORT:-8188}" \
  --reserve-vram 0.6 \
  "${LOW_RAM_ARGS[@]}" \
  "$@"
# Không bật --preview-method: CogVideoXWrapper chưa tương thích với live preview
# của ComfyUI core mới (AttributeError latent_rgb_factors_reshape).
