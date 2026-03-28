"""ANIMA module management and pipeline deployment."""

import json
import os
import subprocess
from fastapi import APIRouter
from fastapi.responses import JSONResponse

router = APIRouter(prefix="/v1/anima", tags=["anima"])

ANIMA_MODULES_DIR = os.environ.get("ANIMA_MODULES_DIR", "/opt/anima/modules")
ANIMA_PIPELINES_DIR = os.environ.get("ANIMA_PIPELINES_DIR", "/opt/anima/pipelines")


@router.get("/modules")
async def anima_modules():
    """List available ANIMA modules."""
    modules = []
    scan_dirs = [ANIMA_MODULES_DIR, "/home/jetson/anima-modules"]

    for scan_dir in scan_dirs:
        if not os.path.isdir(scan_dir):
            continue
        for entry in os.listdir(scan_dir):
            manifest_path = os.path.join(scan_dir, entry, "anima_module.yaml")
            if os.path.exists(manifest_path):
                try:
                    import yaml
                    with open(manifest_path) as f:
                        manifest = yaml.safe_load(f)
                    module_info = _flatten_manifest(manifest, entry)
                    modules.append(module_info)
                except Exception as e:
                    modules.append({"name": entry, "error": str(e)})

    if not modules:
        modules = _simulated_modules()

    return {"modules": modules, "count": len(modules)}


@router.post("/deploy")
async def anima_deploy(payload: dict):
    """Deploy an ANIMA pipeline from docker-compose YAML."""
    import re

    compose_yaml = payload.get("compose_yaml", "")
    pipeline_name = payload.get("pipeline_name", "default")

    if not compose_yaml:
        return JSONResponse(status_code=400, content={"error": "compose_yaml is required"})

    # Sanitize pipeline name — alphanumeric + hyphens only, prevent path traversal
    pipeline_name = re.sub(r'[^a-zA-Z0-9\-]', '', pipeline_name)
    if not pipeline_name:
        pipeline_name = "default"

    os.makedirs(ANIMA_PIPELINES_DIR, exist_ok=True)
    compose_path = os.path.join(ANIMA_PIPELINES_DIR, f"{pipeline_name}.yaml")
    if not os.path.realpath(compose_path).startswith(os.path.realpath(ANIMA_PIPELINES_DIR)):
        return JSONResponse(status_code=403, content={"error": "Path traversal blocked"})

    with open(compose_path, "w") as f:
        f.write(compose_yaml)

    try:
        result = subprocess.run(
            ["docker", "compose", "-f", compose_path, "-p", f"anima-{pipeline_name}", "up", "-d"],
            capture_output=True, text=True, timeout=120
        )
        return {
            "status": "deployed" if result.returncode == 0 else "failed",
            "pipeline": pipeline_name,
            "exit_code": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr,
            "compose_path": compose_path,
        }
    except subprocess.TimeoutExpired:
        return JSONResponse(status_code=408, content={"error": "Deploy timed out after 120s"})


@router.get("/status")
async def anima_status():
    """Get status of running ANIMA pipelines."""
    pipelines = []
    if os.path.isdir(ANIMA_PIPELINES_DIR):
        for fname in os.listdir(ANIMA_PIPELINES_DIR):
            if fname.endswith(".yaml"):
                pipeline_name = fname.replace(".yaml", "")
                compose_path = os.path.join(ANIMA_PIPELINES_DIR, fname)
                try:
                    result = subprocess.run(
                        ["docker", "compose", "-f", compose_path, "-p", f"anima-{pipeline_name}", "ps", "--format", "json"],
                        capture_output=True, text=True, timeout=10
                    )
                    containers = []
                    if result.stdout.strip():
                        for line in result.stdout.strip().split("\n"):
                            try:
                                containers.append(json.loads(line))
                            except json.JSONDecodeError:
                                pass
                    pipelines.append({
                        "name": pipeline_name, "compose_path": compose_path,
                        "containers": containers, "status": "running" if containers else "stopped",
                    })
                except (subprocess.TimeoutExpired, FileNotFoundError):
                    pipelines.append({"name": pipeline_name, "status": "unknown", "error": "Could not query status"})
    return {"pipelines": pipelines}


@router.post("/stop")
async def anima_stop(payload: dict):
    """Stop an ANIMA pipeline."""
    pipeline_name = payload.get("pipeline_name", "default")
    compose_path = os.path.join(ANIMA_PIPELINES_DIR, f"{pipeline_name}.yaml")

    if not os.path.exists(compose_path):
        return JSONResponse(status_code=404, content={"error": f"Pipeline {pipeline_name} not found"})

    try:
        result = subprocess.run(
            ["docker", "compose", "-f", compose_path, "-p", f"anima-{pipeline_name}", "down"],
            capture_output=True, text=True, timeout=60
        )
        return {"status": "stopped" if result.returncode == 0 else "failed", "pipeline": pipeline_name,
                "exit_code": result.returncode, "stdout": result.stdout, "stderr": result.stderr}
    except subprocess.TimeoutExpired:
        return JSONResponse(status_code=408, content={"error": "Stop timed out"})


def _flatten_manifest(manifest: dict, fallback_name: str) -> dict:
    """Flatten anima_module.yaml structure into flat JSON."""
    module = manifest.get("module", {})
    interface = manifest.get("interface", {})
    hardware = manifest.get("hardware", {})
    performance = manifest.get("performance", {})
    safety = manifest.get("safety", {})
    container = manifest.get("container", {})

    return {
        "schema_version": manifest.get("schema_version", "1.0"),
        "name": module.get("name", fallback_name),
        "version": module.get("version", "0.0.0"),
        "display_name": module.get("display_name", fallback_name),
        "description": module.get("description", ""),
        "category": module.get("category", "unknown"),
        "container_image": container.get("image", f"ghcr.io/aiflowlabs/anima-{fallback_name}:latest"),
        "capabilities": [{"type": c.get("type", ""), "subtype": c.get("subtype")} for c in manifest.get("capabilities", {}).get("provides", [])],
        "inputs": [{"name": i.get("name", ""), "ros2_type": i.get("ros2_type", ""), "encoding": i.get("encoding"), "min_hz": i.get("min_hz")} for i in interface.get("inputs", [])],
        "outputs": [{"name": o.get("name", ""), "ros2_type": o.get("ros2_type", ""), "typical_hz": o.get("typical_hz")} for o in interface.get("outputs", [])],
        "hardware_platforms": [{"name": p.get("name", ""), "backends": p.get("backends", [])} for p in hardware.get("platforms", [])],
        "performance_profiles": [{"platform": p.get("platform", ""), "model": p.get("model"), "backend": p.get("backend", ""), "fps": p.get("fps"), "latency_p50_ms": p.get("latency_p50_ms"), "memory_mb": p.get("memory_mb")} for p in performance.get("profiles", [])],
        "failure_mode": safety.get("failure_mode"),
        "timeout_ms": safety.get("timeout_ms"),
        "health_topic": safety.get("health_topic"),
    }


def _simulated_modules() -> list:
    """Return simulated ANIMA modules for dev/testing."""
    return [
        {"schema_version": "1.0", "name": "petra", "version": "0.1.0", "display_name": "PETRA", "description": "Foundation depth perception model", "category": "perception.depth", "container_image": "ghcr.io/aiflowlabs/anima-petra:0.1.0", "capabilities": [{"type": "depth_prediction", "subtype": "relative_depth"}], "inputs": [{"name": "depth_image", "ros2_type": "sensor_msgs/msg/Image", "encoding": ["32FC1"], "min_hz": 1}], "outputs": [{"name": "features", "ros2_type": "std_msgs/msg/Float32MultiArray", "typical_hz": 10}], "hardware_platforms": [{"name": "jetson", "backends": ["tensorrt", "cuda"]}], "performance_profiles": [{"platform": "jetson_tensorrt", "model": "petra-25m", "backend": "tensorrt", "fps": 30, "latency_p50_ms": 35, "memory_mb": 512}], "failure_mode": "returns_empty", "timeout_ms": 5000, "health_topic": "/anima/petra/health"},
        {"schema_version": "1.0", "name": "chronos", "version": "0.1.0", "display_name": "CHRONOS", "description": "Multi-object tracking and temporal reasoning", "category": "perception.tracking", "container_image": "ghcr.io/aiflowlabs/anima-chronos:0.1.0", "capabilities": [{"type": "object_tracking", "subtype": "multi_object"}], "inputs": [{"name": "detections", "ros2_type": "vision_msgs/msg/Detection2DArray", "encoding": None, "min_hz": 5}], "outputs": [{"name": "tracks", "ros2_type": "vision_msgs/msg/Detection2DArray", "typical_hz": 15}], "hardware_platforms": [{"name": "jetson", "backends": ["tensorrt", "cuda"]}, {"name": "linux_x86", "backends": ["cuda", "cpu"]}], "performance_profiles": [{"platform": "jetson_tensorrt", "model": "chronos-s", "backend": "tensorrt", "fps": 25, "latency_p50_ms": 40, "memory_mb": 384}], "failure_mode": "returns_empty", "timeout_ms": 3000, "health_topic": "/anima/chronos/health"},
        {"schema_version": "1.0", "name": "pygmalion", "version": "0.1.0", "display_name": "PYGMALION", "description": "Vision-Language-Action model for robot control", "category": "action.vla", "container_image": "ghcr.io/aiflowlabs/anima-pygmalion:0.1.0", "capabilities": [{"type": "vision_language_action", "subtype": "smolvla"}], "inputs": [{"name": "camera", "ros2_type": "sensor_msgs/msg/Image", "encoding": ["rgb8"], "min_hz": 5}, {"name": "robot_state", "ros2_type": "sensor_msgs/msg/JointState", "encoding": None, "min_hz": 10}], "outputs": [{"name": "action", "ros2_type": "std_msgs/msg/Float32MultiArray", "typical_hz": 10}], "hardware_platforms": [{"name": "jetson", "backends": ["tensorrt", "cuda"]}], "performance_profiles": [{"platform": "jetson_tensorrt", "model": "smolvla-base", "backend": "tensorrt", "fps": 10, "latency_p50_ms": 100, "memory_mb": 2048}], "failure_mode": "hold_last", "timeout_ms": 10000, "health_topic": "/anima/pygmalion/health"},
    ]
