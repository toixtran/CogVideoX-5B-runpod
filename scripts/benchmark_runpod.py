#!/usr/bin/env python3
"""So sánh GPU RunPod Serverless cho MiniMax-H3 Q4_K 4 bước: VRAM, thời gian, cold start, chi phí.

Mỗi endpoint (cùng image >= 1.4.3 để handler trả "metrics", cùng cached model, max workers = 1)
chạy: chờ về 0 worker → 1 + N job liên tiếp → (tuỳ chọn) chờ về 0 lần nữa → 1 job. Mỗi job đổi seed và
thêm "Take i." vào prompt để ComfyUI không trả kết quả cache (như thực tế: mỗi request prompt khác);
cùng dãy seed/prompt cho mọi endpoint. Job lạnh/nóng xác định theo worker_job_index của handler
(1 = job đầu của worker, có load model) vì RunPod có thể chuyển job sang worker khác.

    RUNPOD_API_KEY=... python3 scripts/benchmark_runpod.py \\
        --endpoint "A6000=abc123@1.22" --endpoint "RTX5090=def456@1.58" \\
        --image comfyui/input/chess_landscape.jpg --warm 3 --cold-again

--endpoint NHÃN=ID@USD_MỖI_GIỜ. Kết quả: bảng markdown ra stdout, số liệu thô ra --json.

Định nghĩa:
  exec        executionTime của RunPod (handler chạy, gồm load model nếu worker mới).
  cold start  delayTime (xếp hàng + bật worker + kéo image nếu host chưa có + khởi động ComfyUI)
              + phần exec job lạnh dài hơn exec nóng trung bình (load model vào RAM/VRAM).
  chi phí     RunPod tính tiền từ lúc worker bật tới khi tắt: job nóng = exec x giá/giây;
              job lạnh cộng thêm cold start. Chia cho độ dài âm thanh (length / 24 fps).
"""
import argparse
import base64
import json
import os
import statistics
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).parent.parent
FPS = 24


def call(url, api_key, body=None, timeout=60):
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json", "Authorization": f"Bearer {api_key}",
                                          "User-Agent": "comfyui-video-runpod-benchmark"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def wait_idle(base, api_key, label):
    """Chờ không còn worker đang chạy (container tắt) để job kế tiếp là job lạnh thật. Worker "idle"
    của RunPod là container đã dừng, host giữ sẵn image: job kế tiếp vẫn phải khởi động lại."""
    announced = False
    while True:
        workers = call(f"{base}/health", api_key)["workers"]
        if workers.get("running", 0) == 0:
            return
        if not announced:
            print(f"  [{label}] chờ worker tắt: {workers}", flush=True)
            announced = True
        time.sleep(10)


def run_job(base, api_key, body, label, phase):
    job = call(f"{base}/run", api_key, body)
    start = time.time()
    while True:
        time.sleep(3)
        status = call(f"{base}/status/{job['id']}", api_key)
        if status["status"] in ("COMPLETED", "FAILED", "CANCELLED", "TIMED_OUT"):
            break
    wall = time.time() - start
    if status["status"] != "COMPLETED" or "error" in (status.get("output") or {}):
        sys.exit(f"[{label}] job {phase} lỗi: " + json.dumps(status, ensure_ascii=False)[:3000])
    out = status["output"]
    metrics = out.get("metrics", {})
    row = {
        "kind": "cold" if metrics.get("worker_job_index") == 1 else "warm",
        "phase": phase,
        "job_id": job["id"],
        "worker_id": status.get("workerId"),
        "delay_s": status.get("delayTime", 0) / 1000,
        "exec_s": status.get("executionTime", 0) / 1000,
        "wall_s": round(wall, 1),
        **metrics,
    }
    print(f"  [{label}] {phase} ({row['kind']}, worker {row['worker_id']}): delay {row['delay_s']:.1f}s exec {row['exec_s']:.1f}s "
          f"VRAM đỉnh {row.get('vram_peak_mib')}/{row.get('vram_total_mib')} MiB ({row.get('gpu')})", flush=True)
    return row, out


def summarize(label, price_h, rows, audio_s):
    price_s = price_h / 3600
    colds = [r for r in rows if r["kind"] == "cold"]
    warms = [r for r in rows if r["kind"] == "warm"]
    if not warms:
        sys.exit(f"[{label}] không có job nóng nào — tăng --warm")
    warm_exec = statistics.mean(r["exec_s"] for r in warms)
    cold_starts = [r["delay_s"] + max(0.0, r["exec_s"] - warm_exec) for r in colds]
    return {
        "label": label,
        "gpu": rows[0].get("gpu"),
        "price_per_hour": price_h,
        "vram_total_mib": rows[0].get("vram_total_mib"),
        "vram_peak_mib": max(r.get("vram_peak_mib") or 0 for r in rows),
        "warm_exec_s": round(warm_exec, 1),
        "warm_exec_stdev_s": round(statistics.stdev(r["exec_s"] for r in warms), 1) if len(warms) > 1 else None,
        "cold_start_s": [round(c, 1) for c in cold_starts],
        "cold_total_s": [round(r["delay_s"] + r["exec_s"], 1) for r in colds],
        "cost_warm_video": round(warm_exec * price_s, 4),
        "cost_warm_per_audio_s": round(warm_exec * price_s / audio_s, 5),
        "cost_cold_video": [round((c + warm_exec) * price_s, 4) for c in cold_starts],
        "rows": rows,
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--endpoint", action="append", required=True, help="NHÃN=ID@USD_MỖI_GIỜ")
    p.add_argument("--workflow", default=str(ROOT / "workflows/api/minimax_h3_i2v_turbo4_q4k_dynamic.json"))
    p.add_argument("--image", default=str(ROOT / "comfyui/input/chess_landscape.jpg"))
    p.add_argument("--length", type=int, default=158, help="số frame, lưới 17k+5 (158 = 6.58s)")
    p.add_argument("--seed", type=int, default=42, help="job thứ i dùng seed + i")
    p.add_argument("--warm", type=int, default=3, help="số job nóng sau job lạnh")
    p.add_argument("--cold-again", action="store_true", help="chờ worker tắt rồi đo thêm 1 job lạnh (host đã có image)")
    p.add_argument("--json", default="benchmark_runpod.json")
    p.add_argument("--save-video", help="thư mục lưu video job đầu tiên của mỗi endpoint")
    args = p.parse_args()

    api_key = os.environ.get("RUNPOD_API_KEY") or sys.exit("Thiếu RUNPOD_API_KEY")
    if (args.length - 5) % 17:
        sys.exit("--length phải thuộc lưới 17k+5 (vd. 141, 158)")
    audio_s = args.length / FPS

    wf = json.load(open(args.workflow))
    image_name = "input_" + Path(args.image).name
    wf["5"]["inputs"]["image"] = image_name
    wf["2"]["inputs"]["length"] = args.length
    image = {"name": image_name, "image": base64.b64encode(Path(args.image).read_bytes()).decode()}
    prompt = wf["2"]["inputs"]["prompt"]

    def body(i):
        job_wf = json.loads(json.dumps(wf))
        job_wf["8"]["inputs"]["noise_seed"] = args.seed + i
        job_wf["2"]["inputs"]["prompt"] = f"{prompt} Take {i + 1}."
        return {"input": {"workflow": job_wf, "images": [image]}}

    results = []
    for spec in args.endpoint:
        label, rest = spec.split("=", 1)
        endpoint_id, price = rest.split("@")
        base = f"https://api.runpod.ai/v2/{endpoint_id}"
        print(f"== {label} ({endpoint_id}, ${price}/h)", flush=True)
        rows = []
        wait_idle(base, api_key, label)
        row, out = run_job(base, api_key, body(0), label, "first")
        rows.append(row)
        if args.save_video:
            Path(args.save_video).mkdir(parents=True, exist_ok=True)
            for item in out.get("images", [])[:1]:
                Path(args.save_video, f"{label}_{Path(args.workflow).stem}.mp4").write_bytes(base64.b64decode(item["data"]))
        for i in range(args.warm):
            rows.append(run_job(base, api_key, body(i + 1), label, f"next{i + 1}")[0])
        if args.cold_again:
            wait_idle(base, api_key, label)
            rows.append(run_job(base, api_key, body(args.warm + 1), label, "after_idle")[0])
        results.append(summarize(label, float(price), rows, audio_s))
        Path(args.json).write_text(json.dumps({"audio_s": audio_s, "results": results}, indent=2, ensure_ascii=False))

    print(f"\n{Path(args.workflow).stem}, {args.length} frame = {audio_s:.2f}s video+âm thanh, seed {args.seed}+i\n")
    print("| | GPU | VRAM đỉnh | Gen nóng | Cold start | $/video nóng | $/giây âm thanh | $/video lạnh |")
    print("|---|---|---|---|---|---|---|---|")
    for r in results:
        cold = " / ".join(f"{c:.0f}s" for c in r["cold_start_s"])
        cold_cost = " / ".join(f"${c:.4f}" for c in r["cost_cold_video"])
        print(f"| {r['label']} (${r['price_per_hour']}/h) | {r['gpu']} | {r['vram_peak_mib'] / 1024:.1f}/"
              f"{(r['vram_total_mib'] or 0) / 1024:.0f} GB | {r['warm_exec_s']:.1f}s | {cold} | "
              f"${r['cost_warm_video']:.4f} | ${r['cost_warm_per_audio_s']:.5f} | {cold_cost} |")
    print(f"\nSố liệu thô: {args.json}")


if __name__ == "__main__":
    main()
