# Giai đoạn 2 — Triển khai lên RunPod Serverless

Cập nhật theo `runpod-workers/worker-comfyui` 5.10 (09/2026). Khác tài liệu gốc:

- Image `:latest` không có custom node → tự build từ `Dockerfile` (gốc repo).
- Model: **đóng hết vào image** (CogVideoX, T5, RealESRGAN, RIFE) — cold start không tải gì,
  không cần Cached Models hay Network Volume, không khoá datacenter.
- Worker chỉ trả output key `images` → workflow cloud dùng `SaveVideo` (không dùng VHS).
- Ảnh đầu vào gửi **base64** (worker không nhận URL); video trả về dạng **base64** (không dùng S3).

```
Image (RunPod build từ GitHub)
├─ ComfyUI 0.37 (cùng commit với local)
├─ CogVideoXWrapper, Frame-Interpolation
├─ CogVideoX-5b-I2V: transformer + vae + scheduler (~12GB, ghim commit HF)
└─ T5 fp8 (~5GB), RealESRGAN x2, RIFE 4.9
```

## 1. Image: RunPod build từ GitHub

Không cần Docker Hub: RunPod tự build `Dockerfile` ở gốc repo này.

1. RunPod → Settings → Connections → kết nối GitHub (mỗi tài khoản RunPod chỉ nối 1 GitHub).
2. Đẩy code lên `main`, rồi tạo **GitHub Release** (vd. tag `v0.1.0`).
   RunPod chỉ build lại khi có **Release mới** — commit thường không cập nhật endpoint.
3. Giới hạn build của RunPod: `docker build` ≤ 30 phút, cả quá trình ≤ 160 phút, image ≤ 80GB
   (image đã làm phẳng, kèm model: ~31GB giải nén).

Muốn đưa lên **RunPod Hub**: Hub đọc `.runpod/hub.json` (GPU, CUDA) và chạy
`.runpod/tests.json` (workflow cloud, 10 steps, ảnh PNG nhỏ base64) sau mỗi Release.

Cách thay thế: build ở máy rồi đẩy registry — `./docker/build.sh --push`
(→ `toitx/cogvideox-5b-runpod:<TAG>`; repo Private thì thêm Container Registry Auth trên RunPod).

## 2. Tạo Serverless Endpoint

RunPod → Serverless → New Endpoint → **Import Git Repository**:

| Mục | Giá trị |
|---|---|
| Repository / Branch | `toixtran/CogVideoX-5B-runpod` / `main` |
| Dockerfile path | `Dockerfile` |
| GPU (tối đa 3 nhóm, theo ưu tiên) | 1: **24 GB PRO** (RTX 4090) — rẻ nhất tính theo mỗi video vì model vừa 24GB; dự phòng 2: 48 GB PRO (chỉ khi hết 4090). Bỏ nhóm "24 GB" thường |
| CUDA versions (Advanced) | 12.8 và mọi bản mới hơn (image dùng PyTorch cu128) |
| Min / Max workers | 0 / 1 khi test (mỗi worker mới phải kéo image ~31GB); tăng khi có người dùng |
| Execution timeout | ≥ 1200s |
| FlashBoot | Bật |

Không đặt biến `BUCKET_*`: worker trả video MP4 dạng base64 trong `output.images[].data`.

Deploy → lấy **Endpoint ID**; API key ở Settings → API Keys. Để trống ô **Model** (Cached Models):
model đã có sẵn trong image.

## 3. Gửi thử

```bash
RUNPOD_API_KEY=... python3 scripts/runpod_client.py --endpoint-id <ID> \
  --image anh.jpg --prompt "A young man ... static camera." --out video.mp4
```

## Cập nhật workflow (không cần build lại image)

1. Sửa template trong ComfyUI local → **Export (API)** (menu C → File).
2. `python3 scripts/make_cloud_workflow.py ~/Downloads/<file>.json workflows/api/cogvideox_youtube_16x9_cloud.json`
   (đổi VHS → SaveVideo, `load_device` → `main_device`).
3. Backend đọc file mới. Chỉ build lại image khi thêm custom node / model mới.

## Test image trên máy local (trước khi push)

```bash
pkill -f "python main.py"        # tắt ComfyUI local (không đủ GPU/RAM cho hai bản)
./docker/test_local.sh           # giả lập worker ở http://localhost:8000
python3 scripts/runpod_client.py --url http://localhost:8000 \
  --workflow workflows/api/cogvideox_youtube_16x9_local.json --image anh.jpg --prompt "..."
docker rm -f cogvideox-worker
```

`*_local.json` giữ `offload_device` cho GPU 12GB; `*_cloud.json` dùng `main_device` cho 24GB.
