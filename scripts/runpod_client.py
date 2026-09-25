#!/usr/bin/env python3
"""Gửi 1 job tạo video tới worker-comfyui (RunPod thật hoặc container chạy thử ở local).

    # RunPod
    RUNPOD_API_KEY=... python3 scripts/runpod_client.py --endpoint-id abc123 \\
        --image anh.jpg --prompt "..." --out video.mp4
    # Container local (docker/test_local.sh)
    python3 scripts/runpod_client.py --url http://localhost:8000 --image anh.jpg --prompt "..."

Đây cũng là phần lõi backend Giai đoạn 3: chèn prompt/ảnh/seed vào workflow API rồi
gọi /run, hỏi /status tới khi xong. Chỉ dùng thư viện chuẩn.
"""
import argparse
import base64
import json
import os
import random
import sys
import time
import urllib.request
from pathlib import Path

# ID node trong workflows/api/*.json (giữ nguyên khi export lại từ template).
PROMPT_NODE, IMAGE_NODE, SAMPLER_NODE = "2", "5", "8"


def call(url, api_key, body=None):
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json"})
    if api_key:
        req.add_header("Authorization", f"Bearer {api_key}")
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


parser = argparse.ArgumentParser()
target = parser.add_mutually_exclusive_group(required=True)
target.add_argument("--endpoint-id", help="ID endpoint RunPod Serverless")
target.add_argument("--url", help="URL worker chạy local, vd. http://localhost:8000")
parser.add_argument("--workflow", default=str(Path(__file__).parent.parent / "workflows/api/cogvideox_youtube_16x9_cloud.json"))
parser.add_argument("--image", required=True)
parser.add_argument("--prompt", required=True)
parser.add_argument("--seed", type=int, default=None, help="mặc định: ngẫu nhiên")
parser.add_argument("--steps", type=int, default=None)
parser.add_argument("--out", default="video.mp4")
args = parser.parse_args()

base = args.url.rstrip("/") if args.url else f"https://api.runpod.ai/v2/{args.endpoint_id}"
api_key = os.environ.get("RUNPOD_API_KEY")

wf = json.load(open(args.workflow))
image_name = "input_" + Path(args.image).name
wf[PROMPT_NODE]["inputs"]["prompt"] = args.prompt
wf[IMAGE_NODE]["inputs"]["image"] = image_name
wf[SAMPLER_NODE]["inputs"]["seed"] = args.seed if args.seed is not None else random.randint(0, 2**32 - 1)
if args.steps:
    wf[SAMPLER_NODE]["inputs"]["steps"] = args.steps

image_b64 = base64.b64encode(Path(args.image).read_bytes()).decode()
body = {"input": {"workflow": wf, "images": [{"name": image_name, "image": image_b64}]}}
if len(json.dumps(body)) > 9_500_000:
    sys.exit("Request > ~10MB (giới hạn /run của RunPod): hãy thu nhỏ ảnh xuống ~1280px.")

job = call(f"{base}/run", api_key, body)
print(f"job {job['id']} (seed {wf[SAMPLER_NODE]['inputs']['seed']})", flush=True)
start = time.time()
while True:
    time.sleep(5)
    status = call(f"{base}/status/{job['id']}", api_key)
    print(f"  {int(time.time() - start)}s {status['status']}", flush=True)
    if status["status"] in ("COMPLETED", "FAILED", "CANCELLED", "TIMED_OUT"):
        break

if status["status"] != "COMPLETED":
    sys.exit(json.dumps(status, indent=2, ensure_ascii=False)[:3000])
for item in status["output"]["images"]:
    Path(args.out).write_bytes(base64.b64decode(item["data"]))
    print("video:", args.out)
