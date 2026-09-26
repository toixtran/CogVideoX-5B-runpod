#!/usr/bin/env bash
# Cài đặt ComfyUI + custom nodes cho thử nghiệm CogVideoX / HunyuanVideo.
# Chạy lại an toàn (idempotent). Yêu cầu: git, uv, driver NVIDIA >= 570 (CUDA 12.8).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMFY="$ROOT/comfyui"

clone() { [ -d "$2/.git" ] || git clone --depth 1 "$1" "$2"; }

clone https://github.com/comfyanonymous/ComfyUI.git "$COMFY"
clone https://github.com/Comfy-Org/ComfyUI-Manager.git         "$COMFY/custom_nodes/comfyui-manager"
clone https://github.com/kijai/ComfyUI-CogVideoXWrapper.git     "$COMFY/custom_nodes/ComfyUI-CogVideoXWrapper"
clone https://github.com/kijai/ComfyUI-HunyuanVideoWrapper.git  "$COMFY/custom_nodes/ComfyUI-HunyuanVideoWrapper"
# Fork molbal: bản city96 ngừng từ 01/2026, không đọc được GGUF MiniMax-H3. Ghim commit đã test.
clone https://github.com/molbal/ComfyUI-GGUF.git                "$COMFY/custom_nodes/ComfyUI-GGUF"
git -C "$COMFY/custom_nodes/ComfyUI-GGUF" fetch -q --depth 1 origin 48de657b3aa830ae6981960e928b31cb51fd16aa && git -C "$COMFY/custom_nodes/ComfyUI-GGUF" checkout -q FETCH_HEAD
clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git "$COMFY/custom_nodes/ComfyUI-VideoHelperSuite"
clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git "$COMFY/custom_nodes/ComfyUI-Frame-Interpolation"

ln -sfn "$ROOT/nodes/free_memory_after_run.py" "$COMFY/custom_nodes/free_memory_after_run.py"

cd "$COMFY"
[ -d .venv ] || uv venv --python 3.12 .venv
PIP=(uv pip install --python .venv/bin/python)

"${PIP[@]}" torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
"${PIP[@]}" -r requirements.txt \
  -r custom_nodes/comfyui-manager/requirements.txt \
  -r custom_nodes/ComfyUI-GGUF/requirements.txt \
  -r custom_nodes/ComfyUI-CogVideoXWrapper/requirements.txt \
  -r custom_nodes/ComfyUI-VideoHelperSuite/requirements.txt \
  huggingface_hub "transformers>=4.49.0" "timm>=1.0.15" kornia scipy
# Bỏ qua 'jax' trong requirements của HunyuanVideoWrapper (chỉ dùng cho tính năng phụ, rất nặng).
# Frame-Interpolation: không cài cupy / opencv-contrib-python — RIFE không cần, và
# opencv-contrib xung đột với opencv-python mà các node khác dùng.

# Workflow mẫu -> hiện trong menu Workflows của ComfyUI
mkdir -p user/default/workflows
cp "$ROOT"/workflows/*.json user/default/workflows/ 2>/dev/null || true

.venv/bin/python -c "import torch; print('torch', torch.__version__, 'CUDA:', torch.cuda.is_available())"
