# CogVideoX-5B-runpod

[![Runpod](https://api.runpod.io/badge/toixtran/CogVideoX-5B-runpod)](https://console.runpod.io/hub/toixtran/CogVideoX-5B-runpod)

Tạo video từ ảnh + prompt bằng **CogVideoX-5B Image-to-Video** trên ComfyUI: làm workflow ở máy
local (RTX 4070 Super 12GB), chạy production trên **RunPod Serverless** (GPU 24GB).

```
[Local R&D: ComfyUI]  ── Export (API) ──►  [workflows/api/*.json]  ──►  [RunPod Serverless]
 sửa node, prompt, tham số                  make_cloud_workflow.py       Dockerfile + Cached Model (repo HF)
                                                                          ▲
                                                   backend / scripts/runpod_client.py (prompt + ảnh)
```

Đầu ra template YouTube: MP4 1920×1080, 24fps, ~6 giây.

## Cấu trúc

```
├── workflows/
│   ├── cogvideox_5b_i2v_12gb.json          # UI: bản gốc 720x480 8fps (R&D nhanh)
│   ├── cogvideox_5b_i2v_youtube_16x9.json  # UI: YouTube 1080p 24fps
│   └── api/
│       ├── cogvideox_youtube_16x9_cloud.json  # API cho RunPod (GPU 24GB)
│       └── cogvideox_youtube_16x9_local.json  # API test image trên GPU 12GB
├── scripts/
│   ├── install.sh              # cài ComfyUI + custom nodes vào comfyui/ (không commit)
│   ├── download_models.sh      # CogVideoX-5B-I2V, T5 fp8, RealESRGAN, RIFE (~17GB)
│   ├── run_comfyui.sh          # khởi động ComfyUI local
│   ├── make_cloud_workflow.py  # workflow Export (API) -> bản chạy RunPod
│   ├── runpod_client.py        # gửi job: prompt + ảnh -> video (lõi backend)
│   └── publish_models_hf.sh    # gom model vào 1 repo HF làm Cached Model (chạy 1 lần)
├── nodes/free_memory_after_run.py  # giải phóng VRAM sau mỗi job
├── Dockerfile                  # image worker RunPod (RunPod build từ GitHub)
├── handler.py                  # entrypoint RunPod: dùng lại handler của worker-comfyui
├── .runpod/                    # hub.json (cấu hình RunPod Hub), tests.json (test Hub chạy khi publish)
└── docker/                     # start.sh, build/test local — xem docker/README.md
```

## Chạy local

```bash
./scripts/install.sh           # lần đầu: clone ComfyUI vào comfyui/, tạo .venv
./scripts/download_models.sh   # lần đầu: ~17GB
./scripts/run_comfyui.sh       # http://127.0.0.1:8188
```

Trong ComfyUI: **Workflows** (sidebar trái) → `cogvideox_5b_i2v_youtube_16x9`. Sửa các ô ✏️ xanh
(ảnh, prompt, steps/seed) → **Run**. Video ra ở `comfyui/output/YouTube/`. Ô 📘 trên canvas có
hướng dẫn viết prompt.

```
① Sinh video: Load Image → Resize 720x480 → CogVideoX-5B I2V (fp8) → Decode   (720x480, 8fps)
② Hậu kỳ:     Crop 16:9 → RealESRGAN x2 → 1920x1080 → RIFE x3 (24fps) → MP4 H.264
```

Đo trên RTX 4070 Super: ~7 phút/video ở 25 steps, VRAM đỉnh ~11.5GB, RAM đỉnh ~22GB.

### Tham số R&D

| Node | Tham số | Mặc định | Ghi chú |
|---|---|---|---|
| Load CogVideoX | `quantization` | `fp8_e4m3fn` | Bắt buộc với 12GB |
| Load CogVideoX | `load_device` | `offload_device` | Bắt buộc với 12GB: wrapper đưa model bf16 (~11GB) lên GPU *trước* khi ép fp8 |
| Sampler | `steps` | 20 | 20–30 để thử; tăng 25–30 nếu thiếu chi tiết (mỗi step thêm ~5% thời gian GPU) |
| RIFE VFI | `ensemble` | `false` | Nhanh hơn; `true` nội suy mượt hơn chút nhưng chậm hơn |
| Sampler | `cfg` | 6.0 | 5–7 |
| Sampler | `seed` | `randomize` | Đổi seed = đổi chuyển động; ưng thì chuyển `fixed` |
| Sampler | `num_frames` | 49 | CogVideoX 1.0 train ở 49 khung — không tăng |
| ImageEncode | `noise_aug_strength` | 0.05 | 0.08–0.1 nếu gần như đứng im; 0.02 nếu rung |

- **Prompt** (tiếng Anh, 50–100 từ): tả đúng nhân vật/bối cảnh trong ảnh → cử động nhỏ nhìn thấy
  được (cười, gật, vẫy tay, tóc bay) → máy quay. Tránh hành động lớn (đi, chạy, quay người).
- **Ảnh**: ngang, ≥1280px; ảnh nhỏ thì video mờ dù đã upscale. PNG nền trong suốt: ghép lên nền trắng trước.
- CogVideoX 1.0 chỉ train ở **720×480**; muốn 720p gốc phải đổi sang CogVideoX 1.5 (nặng hơn nhiều).

### Vì sao `run_comfyui.sh` khác tài liệu gốc

- Không `--highvram`: ở ComfyUI hiện tại cờ này tắt dynamic VRAM và ép giữ mọi model trên GPU → OOM.
- `--disable-pinned-memory --cache-none` chỉ bật khi RAM < 48GB: máy 31GB bị Linux OOM-kill ComfyUI
  ("Failed to fetch") vì ComfyUI ghim tới ~75% RAM cộng CogVideoXWrapper load model ngoài tầm quản lý.
  Từ 48GB giữ pinned memory để model lớn hơn VRAM (MiniMax-H3) chuyển RAM → GPU nhanh.
- Không live preview: CogVideoXWrapper chưa tương thích với preview của ComfyUI mới.
- `nodes/free_memory_after_run.py`: CogVideoXWrapper tự đưa model lên GPU, đi vòng qua bộ quản lý
  VRAM của ComfyUI → ~5.7GB bị giữ giữa các lần chạy và lần sau báo "Not enough GPU memory".
  Extension tự *Unload Models and Execution Cache* sau mỗi job (đổi lại: load lại model ~30–50s).

## MiniMax-H3 (video + âm thanh)

Model thứ hai, chạy native trong ComfyUI 0.37 (không cần custom node). File (~44GB, từ
[Comfy-Org/MiniMax-H3](https://huggingface.co/Comfy-Org/MiniMax-H3)) — gom sẵn ở repo HF private
`toixtran/minimax-h3-comfy`, cùng cấu trúc thư mục `comfyui/models/`:

| Thư mục | File |
|---|---|
| diffusion_models | `minimax_h3_fl2va_pruned_int8_convrot` (21GB) |
| text_encoders | `qwen3vl_32b_minimax_h3_nvfp4_awq` (15.7GB) |
| vae | `minimax_h3_video_vae_fp16` (5.2GB), `minimax_h3_audio_vae_fp32` |
| loras | `minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16` |

- UI: `workflows/minimax_h3_i2v_official.json` (template chính thức). API/benchmark:
  `workflows/api/minimax_h3_i2v_turbo.json` — 864×480, 5s (124 frame), turbo LoRA 6 bước, seed 42.
- VAE video dùng bản **fp16** thay cho `int8_convrot` của template: bản int8 gọi kernel `comfy_kitchen`
  build cho CUDA 13 → lỗi `CUDA driver version is insufficient` với driver 570 (CUDA 12.8).
- Cần RAM lớn: ComfyUI dùng ~38GB RAM, VRAM ~11.6GB. RTX 4070 Super (RAM 64GB): **182s**/video
  (sampling 24.5 s/bước).
- **License** (MiniMax H3 Community): không dùng tại Mỹ, EU, Anh, Hàn Quốc (kể cả hosted);
  sản phẩm thương mại phải hiển thị "MiniMax H3". Trên RunPod chỉ chọn data center ngoài các vùng đó.

## Đưa lên RunPod

**RunPod Hub**: repo có sẵn `.runpod/hub.json` và `.runpod/tests.json`. Vào RunPod → Hub → Add your repo,
chọn repo này, rồi tạo **GitHub Release** để Hub build và chạy test (trước đó đưa model lên HF — xem docker/README.md mục 0).

Tạo endpoint thủ công: xem [docker/README.md](docker/README.md): tạo endpoint từ GitHub repo này (Release để build), Cached Model
`toixtran/cogvideox-5b-i2v-comfy`, gửi thử bằng `scripts/runpod_client.py`.

Đổi workflow không cần build lại image: sửa trong ComfyUI → **Export (API)** (menu C → File) →
`python3 scripts/make_cloud_workflow.py <file>.json workflows/api/cogvideox_youtube_16x9_cloud.json`.
Giữ nguyên ID node mà backend ghi vào: prompt `2`, ảnh `5`, seed/steps `8`.

## License

Code trong repo dùng tự do. CogVideoX-5B tuân theo
[CogVideoX License](https://huggingface.co/THUDM/CogVideoX-5b-I2V/blob/main/LICENSE) — kiểm tra
điều khoản trước khi dùng thương mại.
