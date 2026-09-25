"""Tải file lúc build image: python fetch_models.py <url> <đích> [<url> <đích> ...]

Dùng thay cho `ADD <url>`: build RunPod Hub fail ngay, không log, khi Dockerfile có ADD từ URL.
Chỉ dùng thư viện chuẩn; thử lại 3 lần mỗi file, lỗi thì thoát mã khác 0 để build dừng.
"""
import os
import shutil
import sys
import time
import urllib.request

args = sys.argv[1:]
if not args or len(args) % 2:
    sys.exit("cần các cặp <url> <đích>")

for url, dst in zip(args[::2], args[1::2]):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    for attempt in range(1, 4):
        try:
            print(f"tải {url} -> {dst} (lần {attempt})", flush=True)
            with urllib.request.urlopen(url, timeout=60) as r, open(dst + ".part", "wb") as f:
                shutil.copyfileobj(r, f, 16 << 20)
            os.replace(dst + ".part", dst)
            print(f"  xong {os.path.getsize(dst) / 1e9:.2f} GB", flush=True)
            break
        except Exception as e:
            print(f"  lỗi: {e}", flush=True)
            if attempt == 3:
                sys.exit(f"tải thất bại: {url}")
            time.sleep(10 * attempt)
