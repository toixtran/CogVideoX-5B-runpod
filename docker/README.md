# Giai đoạn 2 — Triển khai lên RunPod Serverless

Cập nhật theo `runpod-workers/worker-comfyui` 5.10 (09/2026). Khác tài liệu gốc:

- Image `:latest` không có custom node → tự build từ `Dockerfile` (gốc repo).
- Model: gom hết (CogVideoX, T5, RealESRGAN, RIFE) vào **1 repo Hugging Face** rồi dùng làm
  **Cached Model** của endpoint — cold start không tải gì, không tính tiền thời gian tải, không khoá
  datacenter. Image chỉ có phần mềm (build RunPod Hub fail không log khi có ~17GB model trong image).
- Worker chỉ trả output key `images` → workflow cloud dùng `SaveVideo` (không dùng VHS).
- Ảnh đầu vào gửi **base64** (worker không nhận URL); video trả về dạng **base64** (không dùng S3).

```
RunPod Cached Model (ô "Model")                    Image (RunPod build từ GitHub)
toixtran/cogvideox-5b-i2v-comfy (~17GB) ─────┐     ├─ ComfyUI 0.37 (cùng commit với local)
├─ CogVideoX-5b-I2V/ transformer, vae, sched │     ├─ CogVideoXWrapper, Frame-Interpolation
├─ text_encoders/t5xxl_fp8_e4m3fn            │     └─ start.sh: symlink từ cache vào ComfyUI
├─ upscale_models/RealESRGAN_x2plus          └────────►
└─ rife/rife49
```

## 0. Đưa model lên Hugging Face (làm 1 lần)

```bash
export HF_TOKEN=hf_...                  # token quyền write: https://huggingface.co/settings/tokens
./scripts/publish_models_hf.sh          # -> toixtran/cogvideox-5b-i2v-comfy (private)
# HF_REPO=<user>/<tên> PRIVATE=false ./scripts/publish_models_hf.sh   # đổi tên / để public
```

Script tải ~17GB vào `hf-models/` (tải tiếp nếu bị ngắt), thêm README + LICENSE gốc của từng model,
rồi upload (chạy lại là upload tiếp). Mạng nhà chậm thì chạy trên một **Pod** RunPod rẻ (CPU là đủ,
disk ≥ 40GB): `git clone https://github.com/toixtran/CogVideoX-5B-runpod && cd CogVideoX-5B-runpod`
rồi chạy 2 lệnh trên. Đổi tên repo thì đặt thêm biến `MODEL_REPO=<user>/<tên>` cho endpoint.

## 1. Image: RunPod build từ GitHub

Không cần Docker Hub: RunPod tự build `Dockerfile` ở gốc repo này.

1. RunPod → Settings → Connections → kết nối GitHub (mỗi tài khoản RunPod chỉ nối 1 GitHub).
2. Đẩy code lên `main`, rồi tạo **GitHub Release** (vd. tag `v0.1.0`).
   RunPod chỉ build lại khi có **Release mới** — commit thường không cập nhật endpoint.
3. Giới hạn build của RunPod: `docker build` ≤ 30 phút, cả quá trình ≤ 160 phút, image ≤ 80GB
   (image chỉ có phần mềm, không kèm model).

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
| **Model** (Cached Models) | `toixtran/cogvideox-5b-i2v-comfy` — repo private thì điền thêm HF token (quyền read) |
| GPU (tối đa 3 nhóm, theo ưu tiên) | 1: **24 GB PRO** (RTX 4090) — rẻ nhất tính theo mỗi video vì model vừa 24GB; dự phòng 2: 48 GB PRO (chỉ khi hết 4090). Bỏ nhóm "24 GB" thường |
| CUDA versions (Advanced) | 12.8 và mọi bản mới hơn (image dùng PyTorch cu128) |
| Min / Max workers | 0 / 1 khi test (mỗi worker mới phải kéo image); tăng khi có người dùng |
| Execution timeout | ≥ 1200s |
| FlashBoot | Bật |

Không đặt biến `BUCKET_*`: worker trả video MP4 dạng base64 trong `output.images[].data`.

Deploy → lấy **Endpoint ID**; API key ở Settings → API Keys. Log worker phải có dòng
`cogvideox-5b-runpod: model từ cached model ...`; thấy `ERROR không thấy cached model` thì ô Model
chưa đúng hoặc thiếu HF token (repo private).

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
./docker/test_local.sh           # giả lập worker + Cached Model (mount hf-models/) ở http://localhost:8000
python3 scripts/runpod_client.py --url http://localhost:8000 \
  --workflow workflows/api/cogvideox_youtube_16x9_local.json --image anh.jpg --prompt "..."
docker rm -f cogvideox-worker
```

`*_local.json` giữ `offload_device` cho GPU 12GB; `*_cloud.json` dùng `main_device` cho 24GB.

## Endpoint MiniMax-H3

Cùng image (`toitx/cogvideox-5b-runpod:1.1.0` trở lên — `start.sh` link mọi thư mục `diffusion_models/`,
`text_encoders/`, `vae/`, `loras/`... của repo cached model vào `/comfyui/models/`):

| Mục | Giá trị |
|---|---|
| Container image | `toitx/cogvideox-5b-runpod:1.1.0` |
| Cached model | `toixtran/minimax-h3-comfy` + HF token Read |
| Env | `MODEL_REPO=toixtran/minimax-h3-comfy` |
| GPU | 24 GB PRO (4090) — model 21GB + text encoder 15.7GB chạy nhờ dynamic VRAM |
| CUDA versions | 12.8 trở lên |
| **Data centers** | **Chỉ ngoài Mỹ/EU/Anh/Hàn Quốc** (license H3): vd. CA-MTL-\*, OC-AU-\*, EUR-IS-\*, EUR-NO-\* |

```bash
RUNPOD_API_KEY=... python3 scripts/runpod_client.py --endpoint-id <ID> \
  --workflow workflows/api/minimax_h3_i2v_turbo.json --image comfyui/input/chess_landscape.jpg --seed 42 --out h3.mp4
```

