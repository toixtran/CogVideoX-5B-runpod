# Tự giải phóng VRAM sau mỗi lần chạy — giống bấm Edit → "Unload Models and Execution Cache".
# Cần vì CogVideoXWrapper tự .to(cuda) T5/transformer, đi vòng qua dynamic VRAM của ComfyUI,
# nên VRAM bị giữ lại giữa các lần chạy và lần sau OOM (12GB).
# Đánh đổi: mỗi lần chạy phải load lại model (~30s).
# FREE_MEMORY_AFTER_RUN=0 tắt hook (MiniMax-H3: node native, dynamic VRAM tự quản lý, giữ model
# trong RAM để job sau không phải load lại).
import os

import execution

if os.environ.get("FREE_MEMORY_AFTER_RUN", "1") != "0":
    _task_done = execution.PromptQueue.task_done

    def task_done(self, *args, **kwargs):
        _task_done(self, *args, **kwargs)
        self.set_flag("unload_models", True)
        self.set_flag("free_memory", True)

    execution.PromptQueue.task_done = task_done

NODE_CLASS_MAPPINGS = {}
