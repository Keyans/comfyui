import gc
import logging
import os
import threading
import time
from pathlib import Path

import numpy as np
import torch
from diffusers import QwenImageEditPlusPipeline
from PIL import Image


def _default_model_dir():
    configured = os.environ.get("QWEN_IMAGE_EDIT_MODEL_DIR")
    if configured:
        return Path(configured).expanduser()

    candidates = (
        Path("/data/models/Qwen/Qwen-Image-Edit-2511"),
        Path.home() / "ComfyUI-Shared/models/Qwen/Qwen-Image-Edit-2511",
        Path("/home/hoson1/ai-projects/models/Qwen/Qwen-Image-Edit-2511"),
    )
    return next((path for path in candidates if path.is_dir()), candidates[0])


DEFAULT_MODEL_DIR = _default_model_dir()
LEGACY_MODEL_DIR = Path("/home/hoson1/ai-projects/models/Qwen/Qwen-Image-Edit-2511")
_PIPELINE = None
_PIPELINE_KEY = None
_PIPELINE_LOCK = threading.Lock()
_INFERENCE_LOCK = threading.Lock()
_ACTIVE_INFERENCE_COUNT = 0
_LAST_USED_AT = None
_IDLE_MONITOR_STARTED = False


def _get_boolean_env(name, default):
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() not in {"0", "false", "no", "off"}


def _get_positive_integer_env(name, default):
    raw = os.environ.get(name)
    if raw is None:
        return default
    try:
        value = int(raw)
    except ValueError:
        logging.warning("%s is not an integer; using %s", name, default)
        return default
    if value <= 0:
        logging.warning("%s must be positive; using %s", name, default)
        return default
    return value


IDLE_UNLOAD_ENABLED = _get_boolean_env("QWEN_OFFICIAL_IDLE_UNLOAD_ENABLED", True)
IDLE_UNLOAD_SECONDS = _get_positive_integer_env("QWEN_OFFICIAL_IDLE_UNLOAD_SECONDS", 300)
IDLE_CHECK_INTERVAL_SECONDS = _get_positive_integer_env(
    "QWEN_OFFICIAL_IDLE_CHECK_INTERVAL_SECONDS", 30
)


def _clear_memory():
    gc.collect()
    if torch.cuda.is_available():
        torch.cuda.empty_cache()
        torch.cuda.ipc_collect()
    elif torch.backends.mps.is_available():
        torch.mps.empty_cache()


def _runtime_device():
    if torch.cuda.is_available():
        return "cuda"
    if torch.backends.mps.is_available():
        return "mps"
    return "cpu"


def _normalize_model_dir(model_dir):
    requested = Path(model_dir).expanduser()
    if requested == LEGACY_MODEL_DIR:
        requested = DEFAULT_MODEL_DIR
    normalized = requested.resolve()
    if not normalized.is_dir():
        raise FileNotFoundError(f"Model directory does not exist: {normalized}")
    return normalized


def _resolve_torch_dtype(dtype_name):
    mapping = {
        "bf16": torch.bfloat16,
        "fp16": torch.float16,
        "fp32": torch.float32,
    }
    if dtype_name not in mapping:
        raise ValueError(f"Unsupported dtype: {dtype_name}")
    return mapping[dtype_name]


def _resolve_generator(seed, device):
    normalized_seed = int(seed) % ((1 << 63) - 1)
    generator_device = (
        "cuda" if device.startswith("cuda") and torch.cuda.is_available() else "cpu"
    )
    return torch.Generator(device=generator_device).manual_seed(normalized_seed)


def _tensor_to_pil_image(image_tensor):
    image = image_tensor.detach().cpu().numpy()
    image = np.clip(image * 255.0, 0, 255).astype(np.uint8)
    return Image.fromarray(image)


def _pil_to_tensor(image):
    array = np.asarray(image.convert("RGB"), dtype=np.float32) / 255.0
    return torch.from_numpy(array).unsqueeze(0)


def _collect_input_images(*image_inputs):
    images = []
    for image in image_inputs:
        if image is not None and image.shape[0] > 0:
            images.append(_tensor_to_pil_image(image[0]))
    if not images:
        raise ValueError("At least one input image is required")
    if len(images) > 3:
        raise ValueError("At most three input images are supported")
    return images


def _unload_pipeline_locked():
    global _PIPELINE, _PIPELINE_KEY, _LAST_USED_AT
    pipeline = _PIPELINE
    _PIPELINE = None
    _PIPELINE_KEY = None
    _LAST_USED_AT = None
    if pipeline is not None:
        try:
            pipeline.to("cpu")
        except Exception:
            pass
    _clear_memory()


def _configure_pipeline(pipeline, offload_mode, runtime_device, attention_slicing):
    if attention_slicing:
        pipeline.enable_attention_slicing()
    if offload_mode == "sequential_cpu_offload":
        pipeline.enable_sequential_cpu_offload()
    elif offload_mode == "model_cpu_offload":
        pipeline.enable_model_cpu_offload()
    else:
        pipeline.to(runtime_device)
    pipeline.set_progress_bar_config(disable=None)


def _acquire_pipeline(model_dir, dtype_name, offload_mode, attention_slicing, reload_pipeline):
    global _PIPELINE, _PIPELINE_KEY, _ACTIVE_INFERENCE_COUNT, _LAST_USED_AT
    resolved_model_dir = _normalize_model_dir(model_dir)
    key = (str(resolved_model_dir), dtype_name, offload_mode, bool(attention_slicing))
    runtime_device = _runtime_device()

    with _PIPELINE_LOCK:
        if reload_pipeline or _PIPELINE is None or _PIPELINE_KEY != key:
            _unload_pipeline_locked()
            pipeline = QwenImageEditPlusPipeline.from_pretrained(
                str(resolved_model_dir),
                torch_dtype=_resolve_torch_dtype(dtype_name),
                local_files_only=True,
            )
            _configure_pipeline(
                pipeline, offload_mode, runtime_device, attention_slicing
            )
            _PIPELINE = pipeline
            _PIPELINE_KEY = key
        _ACTIVE_INFERENCE_COUNT += 1
        _LAST_USED_AT = time.monotonic()
    return _PIPELINE, runtime_device


def _release_pipeline():
    global _ACTIVE_INFERENCE_COUNT, _LAST_USED_AT
    with _PIPELINE_LOCK:
        _ACTIVE_INFERENCE_COUNT = max(0, _ACTIVE_INFERENCE_COUNT - 1)
        if _PIPELINE is not None:
            _LAST_USED_AT = time.monotonic()


def _start_idle_monitor():
    global _IDLE_MONITOR_STARTED
    if not IDLE_UNLOAD_ENABLED or _IDLE_MONITOR_STARTED:
        return

    def worker():
        while True:
            time.sleep(IDLE_CHECK_INTERVAL_SECONDS)
            with _PIPELINE_LOCK:
                if _PIPELINE is None or _ACTIVE_INFERENCE_COUNT > 0 or _LAST_USED_AT is None:
                    continue
                if time.monotonic() - _LAST_USED_AT >= IDLE_UNLOAD_SECONDS:
                    _unload_pipeline_locked()

    threading.Thread(
        target=worker, name="qwen-official-idle-unload", daemon=True
    ).start()
    _IDLE_MONITOR_STARTED = True


class QwenOfficialImageEditBridge:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "image1": ("IMAGE",),
                "prompt": ("STRING", {"multiline": True, "default": ""}),
                "negative_prompt": ("STRING", {"multiline": True, "default": " "}),
                "steps": ("INT", {"default": 40, "min": 1, "max": 100}),
                "true_cfg_scale": (
                    "FLOAT",
                    {"default": 4.0, "min": 0.0, "max": 20.0, "step": 0.1},
                ),
                "guidance_scale": (
                    "FLOAT",
                    {"default": 1.0, "min": 0.0, "max": 20.0, "step": 0.1},
                ),
                "seed": ("INT", {"default": 0, "min": 0, "max": 0xFFFFFFFFFFFFFFFF}),
                "width": ("INT", {"default": 768, "min": 256, "max": 2048, "step": 16}),
                "height": ("INT", {"default": 1024, "min": 256, "max": 2048, "step": 16}),
                "num_images_per_prompt": ("INT", {"default": 1, "min": 1, "max": 4}),
                "model_dir": (
                    "STRING",
                    {"default": str(DEFAULT_MODEL_DIR), "advanced": True},
                ),
                "dtype": (
                    ["bf16", "fp16", "fp32"],
                    {"default": "bf16", "advanced": True},
                ),
                "offload_mode": (
                    ["model_cpu_offload", "sequential_cpu_offload", "cuda"],
                    {"default": "model_cpu_offload", "advanced": True},
                ),
                "attention_slicing": (
                    "BOOLEAN",
                    {"default": False, "advanced": True},
                ),
                "reload_pipeline": (
                    "BOOLEAN",
                    {"default": False, "advanced": True},
                ),
            },
            "optional": {
                "image2": ("IMAGE",),
                "image3": ("IMAGE",),
            },
        }

    RETURN_TYPES = ("IMAGE",)
    FUNCTION = "generate"
    CATEGORY = "image/qwen"

    def generate(
        self,
        image1,
        prompt,
        negative_prompt,
        steps,
        true_cfg_scale,
        guidance_scale,
        seed,
        width,
        height,
        num_images_per_prompt,
        model_dir=str(DEFAULT_MODEL_DIR),
        dtype="bf16",
        offload_mode="model_cpu_offload",
        attention_slicing=False,
        reload_pipeline=False,
        image2=None,
        image3=None,
    ):
        input_images = _collect_input_images(image1, image2, image3)
        pipeline, runtime_device = _acquire_pipeline(
            model_dir,
            dtype,
            offload_mode,
            attention_slicing,
            reload_pipeline,
        )
        try:
            with _INFERENCE_LOCK, torch.inference_mode():
                result = pipeline(
                    image=input_images,
                    prompt=prompt,
                    negative_prompt=negative_prompt,
                    generator=_resolve_generator(seed, runtime_device),
                    true_cfg_scale=float(true_cfg_scale),
                    num_inference_steps=int(steps),
                    guidance_scale=float(guidance_scale),
                    num_images_per_prompt=int(num_images_per_prompt),
                    width=int(width),
                    height=int(height),
                )
            if not result.images:
                raise RuntimeError("Qwen pipeline returned no images")
            return (torch.cat([_pil_to_tensor(image) for image in result.images]),)
        finally:
            _release_pipeline()


NODE_CLASS_MAPPINGS = {
    "QwenOfficialImageEditBridge": QwenOfficialImageEditBridge,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "QwenOfficialImageEditBridge": "Qwen Official Image Edit Bridge",
}


_start_idle_monitor()
