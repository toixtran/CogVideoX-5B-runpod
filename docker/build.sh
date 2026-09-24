#!/usr/bin/env bash
# Build image worker (và push nếu có --push).
#
#   ./docker/build.sh                 # build: toitx/cogvideox-5b-runpod:0.1.0
#   ./docker/build.sh --push          # build + push lên Docker Hub
#   IMAGE=ghcr.io/<user>/cogvideox-5b-runpod TAG=0.2.0 ./docker/build.sh --push
#
# Mỗi lần đổi Dockerfile hãy tăng TAG: RunPod cache image theo tag, đẩy đè cùng tag
# thì worker đang chạy có thể vẫn dùng bản cũ.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${IMAGE:-toitx/cogvideox-5b-runpod}"
TAG="${TAG:-0.1.0}"

# RunPod chạy x86_64: ép linux/amd64 để build trên máy khác (vd. Mac M-series) vẫn đúng.
docker build --platform linux/amd64 -f "$ROOT/Dockerfile" -t "$IMAGE:$TAG" "$ROOT"

if [ "${1:-}" = "--push" ]; then
  docker push "$IMAGE:$TAG"
fi
echo "Image: $IMAGE:$TAG"
