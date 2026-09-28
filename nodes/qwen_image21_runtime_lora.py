# LoRA cho Qwen-Image 2.1 áp lúc chạy (y = Wx + s·BAx), không merge vào trọng số.
# LoraLoaderModelOnly vá LoRA vào trọng số int8_convrot bằng requant -> nhiễu lớn với LoRA style
# (Anything2RealCharacters ra ảnh toàn mảng xanh). Cùng cách với ViggleTurboLora nhưng đọc được khoá
# diffusers / PEFT (.default) / ai-toolkit (diffusion_model.) / kohya (lora_down/up, .alpha), và img_mlp
# gộp (gate_up) lẫn tách (gate_layer + proj). Dùng nối tiếp được với ViggleTurboLora.
import json
import re

import torch
import torch.nn.functional as F

import comfy.patcher_extension
import comfy.utils
import folder_paths


def _norm_key(k):
    k = re.sub(r"^(base_model\.model\.|diffusion_model\.|transformer\.)+", "", k)
    return k.replace(".default.", ".").replace("lora_down", "lora_A").replace("lora_up", "lora_B")


def load_lora(path, strength):
    sd, meta = comfy.utils.load_torch_file(path, return_metadata=True)
    sd = {_norm_key(k): v for k, v in sd.items()}
    cfg = json.loads((meta or {}).get("lora_adapter_metadata", "{}"))
    lora = {}
    for k in sd:
        if not k.endswith(".lora_A.weight"):
            continue
        name = k[: -len(".lora_A.weight")]
        a, b = sd[k], sd[name + ".lora_B.weight"]
        if name + ".alpha" in sd:
            scale = float(sd[name + ".alpha"]) / a.shape[0]
        elif "transformer.lora_alpha" in cfg:
            scale = cfg["transformer.lora_alpha"] / cfg.get("transformer.r", a.shape[0])
        else:
            scale = 1.0
        lora[name] = [a, b * (strength * scale)]
    return lora


def _branch(x, ab):
    return F.linear(F.linear(x, ab[0].to(x.dtype)), ab[1].to(x.dtype))


def _add_hooks(dm, lora):
    hooks, mlps = [], {}
    for name, ab in lora.items():
        parent, _, leaf = name.rpartition(".")
        if getattr(dm.get_submodule(parent), "fused", False):
            mlps.setdefault(parent, {})[leaf] = ab
        else:
            hooks.append(dm.get_submodule(name).register_forward_hook(
                lambda m, inp, out, ab=ab: out + _branch(inp[0], ab)))
    # MLP gộp: `out` chạy trong kernel int8 (linear_input_act) không qua hook của nó, nên nhánh LoRA
    # của `out` được cộng vào đầu ra MLP, tính từ đầu ra gate_up (đã có LoRA).
    for parent, p in mlps.items():
        mlp, state = dm.get_submodule(parent), {}

        def gate_up_hook(m, inp, out, p=p, state=state):
            x = inp[0]
            if "gate_up" in p:
                out = out + _branch(x, p["gate_up"])
            elif "gate_layer" in p or "proj" in p:
                half = out.shape[-1] // 2
                delta = torch.zeros_like(out)
                if "gate_layer" in p:
                    delta[..., :half] = _branch(x, p["gate_layer"])
                if "proj" in p:
                    delta[..., half:] = _branch(x, p["proj"])
                out = out + delta
            state["gu"] = out
            return out

        def mlp_hook(m, inp, out, p=p, state=state):
            gu = state.pop("gu")
            if "out" not in p:
                return out
            g, u = gu.chunk(2, -1)
            return out + _branch(F.silu(g) * u, p["out"])

        hooks += [mlp.gate_up.register_forward_hook(gate_up_hook), mlp.register_forward_hook(mlp_hook)]
    return hooks


def _run_with_lora(lora, executor, *args, **kwargs):
    device = args[0].device
    for ab in lora.values():
        if ab[0].device != device:
            ab[0], ab[1] = ab[0].to(device), ab[1].to(device)
    hooks = _add_hooks(executor.class_obj, lora)
    try:  # diffusion model dùng chung giữa các MODEL output: hook không được sống quá lần gọi này
        return executor(*args, **kwargs)
    finally:
        for h in hooks:
            h.remove()


class QwenImage21RuntimeLora:
    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {
            "model": ("MODEL",),
            "lora_name": (folder_paths.get_filename_list("loras"),),
            "strength": ("FLOAT", {"default": 1.0, "min": -4.0, "max": 4.0, "step": 0.05}),
        }}

    RETURN_TYPES = ("MODEL",)
    FUNCTION = "load"
    CATEGORY = "loaders"
    DESCRIPTION = "Qwen-Image 2.1 LoRA applied at runtime (y = Wx + BAx), not merged into int8/bf16 weights."

    def load(self, model, lora_name, strength):
        lora = load_lora(folder_paths.get_full_path_or_raise("loras", lora_name), strength)
        m = model.clone()
        m.add_wrapper_with_key(comfy.patcher_extension.WrappersMP.DIFFUSION_MODEL, f"runtime_lora:{lora_name}",
                               lambda executor, *a, **kw: _run_with_lora(lora, executor, *a, **kw))
        return (m,)


NODE_CLASS_MAPPINGS = {"QwenImage21RuntimeLora": QwenImage21RuntimeLora}
NODE_DISPLAY_NAME_MAPPINGS = {"QwenImage21RuntimeLora": "Qwen-Image 2.1 LoRA (runtime, unmerged)"}
