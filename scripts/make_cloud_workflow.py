#!/usr/bin/env python3
"""Chuyển workflow đã Export (API) từ ComfyUI local thành bản chạy trên RunPod.

    python3 scripts/make_cloud_workflow.py ~/Downloads/workflow_api.json workflows/api/youtube_16x9.json

- VHS_VideoCombine -> CreateVideo + SaveVideo: worker-comfyui chỉ trả về output có key
  "images"; VHS trả "gifs" nên video bị bỏ qua. SaveVideo giữ nguyên node ID để backend
  không phải đổi.
- DownloadAndLoadCogVideoModel: load_device = main_device (GPU 24GB đủ chỗ, load nhanh hơn).
  Thêm --local để giữ offload_device khi test image trên GPU 12GB.
"""
import argparse
import json

parser = argparse.ArgumentParser()
parser.add_argument("src")
parser.add_argument("dst")
parser.add_argument("--local", action="store_true", help="giữ offload_device (test trên GPU 12GB)")
args = parser.parse_args()

wf = json.load(open(args.src))
next_id = max(int(k) for k in wf) + 1

for node_id, node in list(wf.items()):
    inputs = node["inputs"]
    if node["class_type"] == "VHS_VideoCombine":
        wf[str(next_id)] = {"class_type": "CreateVideo",
                            "inputs": {"images": inputs["images"], "fps": inputs["frame_rate"]}}
        wf[node_id] = {"class_type": "SaveVideo", "inputs": {
            "video": [str(next_id), 0],
            "filename_prefix": inputs["filename_prefix"],
            "format": "mp4",
            "format.codec": "h264",
            "format.codec.encoding": "re-encode",
            "format.codec.encoding.crf": inputs.get("crf", 19),
        }}
        next_id += 1
    elif node["class_type"] == "DownloadAndLoadCogVideoModel" and not args.local:
        inputs["load_device"] = "main_device"

json.dump(wf, open(args.dst, "w"), indent=2, ensure_ascii=False)
print(f"-> {args.dst}")
