# CogVideoX-5B-runpod

Tạo video từ ảnh + prompt bằng **CogVideoX-5B Image-to-Video** trên ComfyUI: làm workflow ở máy
local (RTX 4070 Super 12GB), chạy production trên **RunPod Serverless** (GPU 24GB).

```
[Local R&D: ComfyUI]  ── Export (API) ──►  [workflows/api/*.json]  ──►  [RunPod Serverless]
 sửa node, prompt, tham số                  make_cloud_workflow.py       Dockerfile + Cached Model
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
│   └── runpod_client.py        # gửi job: prompt + ảnh -> video (lõi backend)
├── nodes/free_memory_after_run.py  # giải phóng VRAM sau mỗi job
├── Dockerfile                  # image worker RunPod (RunPod build từ GitHub)
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
| Sampler | `steps` | 25 | 20–30 để thử; 40–50 cho bản cuối |
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
- `--disable-pinned-memory --cache-none`: máy 31GB RAM; mặc định ComfyUI ghim tới ~24GB RAM,
  cộng CogVideoXWrapper load model ngoài tầm quản lý → Linux OOM-kill ComfyUI ("Failed to fetch").
- Không live preview: CogVideoXWrapper chưa tương thích với preview của ComfyUI mới.
- `nodes/free_memory_after_run.py`: CogVideoXWrapper tự đưa model lên GPU, đi vòng qua bộ quản lý
  VRAM của ComfyUI → ~5.7GB bị giữ giữa các lần chạy và lần sau báo "Not enough GPU memory".
  Extension tự *Unload Models and Execution Cache* sau mỗi job (đổi lại: load lại model ~30–50s).

## Đưa lên RunPod

Xem [docker/README.md](docker/README.md): tạo endpoint từ GitHub repo này (Release để build), Cached Model
`THUDM/CogVideoX-5b-I2V`, gửi thử bằng `scripts/runpod_client.py`.

Đổi workflow không cần build lại image: sửa trong ComfyUI → **Export (API)** (menu C → File) →
`python3 scripts/make_cloud_workflow.py <file>.json workflows/api/cogvideox_youtube_16x9_cloud.json`.
Giữ nguyên ID node mà backend ghi vào: prompt `2`, ảnh `5`, seed/steps `8`.

## License

Code trong repo dùng tự do. CogVideoX-5B tuân theo
[CogVideoX License](https://huggingface.co/THUDM/CogVideoX-5b-I2V/blob/main/LICENSE) — kiểm tra
điều khoản trước khi dùng thương mại.
