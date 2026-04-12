"""GPU info, TensorRT engines, model management."""

import os
import subprocess
from datetime import datetime, timezone
from fastapi import APIRouter, UploadFile, File
from fastapi.responses import JSONResponse
from mlx_backend import mlx_backend_status
from process_manager import process_manager
from sim import is_sim

router = APIRouter(prefix="/v1", tags=["gpu"])

MODELS_DIR = os.environ.get("THOR_MODELS_DIR", "/opt/models")


@router.get("/gpu/info")
async def gpu_info():
    """Get GPU and CUDA information."""
    mlx_status = mlx_backend_status() if is_sim() else None
    if mlx_status:
        total_mb = mlx_status["memory_total_mb"]
        used_mb = min(mlx_status["memory_used_mb"], total_mb) if total_mb else mlx_status["memory_used_mb"]
        return {
            "gpu_name": f"Apple Silicon Metal via {mlx_status['runtime_label']}",
            "cuda_version": None,
            "tensorrt_version": None,
            "memory_total_mb": total_mb,
            "memory_used_mb": used_mb,
            "memory_free_mb": max(total_mb - used_mb, 0),
            "utilization_percent": 0,
            "temperature_c": 0,
            "power_draw_w": 0,
            "backend": "mlx",
            "backend_source": "host_macos",
            "backend_status": "connected",
            "backend_endpoint": mlx_status["base_url"],
            "metal_available": mlx_status["metal_available"],
            "runtime_label": mlx_status["runtime_label"],
            "loaded_models": mlx_status["loaded_models"],
            "cached_models": mlx_status["cached_models"],
            "chip": mlx_status["chip"],
            "platform": mlx_status["platform"],
            "mlx_backend": mlx_status["mlx_backend"],
        }

    info = {
        "gpu_name": "N/A",
        "cuda_version": None,
        "tensorrt_version": None,
        "memory_total_mb": 0,
        "memory_used_mb": 0,
        "memory_free_mb": 0,
        "utilization_percent": 0,
        "temperature_c": 0,
        "power_draw_w": 0,
    }

    # CUDA version
    try:
        result = subprocess.run(["nvcc", "--version"], capture_output=True, text=True, timeout=5)
        for line in result.stdout.split("\n"):
            if "release" in line.lower():
                parts = line.split("release")
                if len(parts) > 1:
                    info["cuda_version"] = parts[1].strip().split(",")[0].strip()
    except FileNotFoundError:
        # Try dpkg
        try:
            result = subprocess.run(["dpkg", "-l", "cuda-toolkit*"], capture_output=True, text=True, timeout=5)
            for line in result.stdout.split("\n"):
                if "cuda-toolkit" in line and line.startswith("ii"):
                    info["cuda_version"] = line.split()[2]
                    break
        except FileNotFoundError:
            pass

    # TensorRT version
    try:
        result = subprocess.run(["dpkg", "-l", "tensorrt*"], capture_output=True, text=True, timeout=5)
        for line in result.stdout.split("\n"):
            if "tensorrt" in line.lower() and line.startswith("ii"):
                info["tensorrt_version"] = line.split()[2]
                break
    except FileNotFoundError:
        pass

    # nvidia-smi (may not be available on all Jetsons)
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,memory.total,memory.used,memory.free,utilization.gpu,temperature.gpu,power.draw",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            parts = [p.strip() for p in result.stdout.strip().split(",")]
            if len(parts) >= 7:
                info["gpu_name"] = parts[0]
                info["memory_total_mb"] = int(float(parts[1]))
                info["memory_used_mb"] = int(float(parts[2]))
                info["memory_free_mb"] = int(float(parts[3]))
                info["utilization_percent"] = float(parts[4])
                info["temperature_c"] = float(parts[5])
                info["power_draw_w"] = float(parts[6])
    except FileNotFoundError:
        pass

    if is_sim():
        info["gpu_name"] = "NVIDIA Jetson Thor GPU (simulated)"
        info["cuda_version"] = "12.6"
        info["tensorrt_version"] = "10.3"
        info["memory_total_mb"] = 65536
        info["memory_used_mb"] = 4096

    return info


@router.get("/gpu/tensorrt/engines")
async def tensorrt_engines():
    """List TensorRT engine files."""
    engines = []
    search_dirs = [MODELS_DIR, "/home/jetson/models", "/tmp/models"]

    for search_dir in search_dirs:
        if not os.path.isdir(search_dir):
            continue
        for root, _, files in os.walk(search_dir):
            for fname in files:
                if fname.endswith((".trt", ".engine", ".plan")):
                    full = os.path.join(root, fname)
                    stat = os.stat(full)
                    engines.append({
                        "name": fname,
                        "path": full,
                        "size_bytes": stat.st_size,
                        "created_at": datetime.fromtimestamp(stat.st_ctime, tz=timezone.utc).isoformat(),
                    })

    return {"engines": engines, "count": len(engines)}


@router.post("/gpu/tensorrt/convert")
async def tensorrt_convert(payload: dict):
    """Convert an ONNX model to TensorRT engine (background process)."""
    onnx_path = payload.get("onnx_path", "")
    output = payload.get("output", "")
    fp16 = payload.get("fp16", False)

    if not onnx_path:
        return JSONResponse(status_code=400, content={"error": "onnx_path required"})
    if not output:
        output = onnx_path.rsplit(".", 1)[0] + ".trt"

    # Validate paths — must be within allowed model directories
    allowed_dirs = [MODELS_DIR, "/home/jetson/models", "/tmp/models"]
    for path in [onnx_path, output]:
        real = os.path.realpath(path)
        if not any(real.startswith(os.path.realpath(d)) for d in allowed_dirs):
            return JSONResponse(status_code=403, content={"error": f"Path must be in allowed model directories: {allowed_dirs}"})

    cmd = ["trtexec", f"--onnx={onnx_path}", f"--saveEngine={output}"]
    if fp16:
        cmd.append("--fp16")

    try:
        managed = process_manager.start(cmd, category="trt_convert")
        return {"pid": managed.pid, "status": "converting", "onnx_path": onnx_path, "output": output}
    except Exception as e:
        return JSONResponse(status_code=500, content={"error": str(e)})


@router.get("/models/list")
async def model_list():
    """List model files."""
    mlx_status = mlx_backend_status() if is_sim() else None
    if mlx_status:
        models = []
        for model in mlx_status["models"]:
            model_id = model.get("id", "")
            models.append({
                "name": model_id.split("/")[-1] if model_id else "Unknown",
                "path": model.get("local_path", model_id),
                "format": "mlx",
                "size_bytes": int(model.get("size_bytes") or 0),
                "last_modified": model.get("pulled_at") or datetime.now(timezone.utc).isoformat(),
            })
        return {"models": models, "count": len(models)}

    models = []
    search_dirs = [MODELS_DIR, "/home/jetson/models"]
    extensions = (".onnx", ".trt", ".engine", ".plan", ".pt", ".pth", ".safetensors", ".bin")

    for search_dir in search_dirs:
        if not os.path.isdir(search_dir):
            continue
        for root, _, files in os.walk(search_dir):
            for fname in files:
                if fname.endswith(extensions):
                    full = os.path.join(root, fname)
                    stat = os.stat(full)
                    ext = fname.rsplit(".", 1)[-1]
                    models.append({
                        "name": fname,
                        "path": full,
                        "format": ext,
                        "size_bytes": stat.st_size,
                        "last_modified": datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat(),
                    })

    if is_sim() and not models:
        models = [
            {"name": "sample.onnx", "path": f"{MODELS_DIR}/sample.onnx", "format": "onnx", "size_bytes": 12345678, "last_modified": datetime.now(timezone.utc).isoformat()},
            {"name": "sample.trt", "path": f"{MODELS_DIR}/sample.trt", "format": "trt", "size_bytes": 8765432, "last_modified": datetime.now(timezone.utc).isoformat()},
        ]

    return {"models": models, "count": len(models)}


MAX_UPLOAD_SIZE = 10 * 1024 * 1024 * 1024  # 10GB max


@router.post("/models/upload")
async def model_upload(file: UploadFile = File(...)):
    """Upload a model file to the device (path-safe, size-limited)."""
    import re

    os.makedirs(MODELS_DIR, exist_ok=True)

    # Sanitize filename — prevent path traversal
    safe_name = os.path.basename(file.filename or "upload.bin")
    safe_name = re.sub(r'[^\w\-.]', '_', safe_name)  # Only alphanumeric, dash, dot
    if not safe_name or safe_name.startswith("."):
        safe_name = "upload.bin"

    dest = os.path.join(MODELS_DIR, safe_name)
    # Verify resolved path stays within MODELS_DIR
    if not os.path.realpath(dest).startswith(os.path.realpath(MODELS_DIR)):
        return JSONResponse(status_code=403, content={"error": "Path traversal blocked"})

    try:
        # Stream to disk in chunks to avoid memory exhaustion
        total_size = 0
        with open(dest, "wb") as f:
            while chunk := await file.read(1024 * 1024):  # 1MB chunks
                total_size += len(chunk)
                if total_size > MAX_UPLOAD_SIZE:
                    f.close()
                    os.remove(dest)
                    return JSONResponse(status_code=413, content={"error": f"File too large (max {MAX_UPLOAD_SIZE // (1024**3)}GB)"})
                f.write(chunk)

        return {"success": True, "path": dest, "size_bytes": total_size, "filename": safe_name}
    except Exception as e:
        return JSONResponse(status_code=500, content={"error": str(e)})
