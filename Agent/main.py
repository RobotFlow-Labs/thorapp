"""
THOR Jetson Agent — localhost-only HTTP/JSON API.

Runs as a systemd service on the Jetson device.
Bound to 127.0.0.1 only (accessed via SSH tunnel from Mac).
"""

import json
import os
import platform
import shutil
import subprocess
import sys
from datetime import datetime, timezone

import psutil
from fastapi import FastAPI
from fastapi.responses import JSONResponse
import uvicorn

app = FastAPI(title="THOR Agent", version="0.1.0")

AGENT_VERSION = "0.1.0"


def _sim_identity() -> dict:
    """Read simulated Jetson identity or detect real hardware."""
    identity_file = "/etc/thor-sim/identity.json"
    if os.path.exists(identity_file):
        with open(identity_file) as f:
            return json.load(f)

    # Real hardware detection (best-effort)
    model = "Unknown"
    jetpack = None

    # Try reading Jetson model
    model_file = "/proc/device-tree/model"
    if os.path.exists(model_file):
        with open(model_file) as f:
            model = f.read().strip().rstrip("\x00")

    # Try reading JetPack version
    jetpack_file = "/etc/nv_tegra_release"
    if os.path.exists(jetpack_file):
        with open(jetpack_file) as f:
            jetpack = f.read().strip()

    return {"model": model, "jetpack": jetpack}


def _detect_docker() -> str | None:
    """Detect Docker version if available."""
    try:
        result = subprocess.run(
            ["docker", "--version"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return None


def _detect_ros2() -> bool:
    """Check if ROS2 is available."""
    try:
        result = subprocess.run(
            ["ros2", "--version"],
            capture_output=True, text=True, timeout=5
        )
        return result.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


@app.get("/v1/health")
async def health():
    """Health check endpoint."""
    return {
        "status": "healthy",
        "agent_version": AGENT_VERSION,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "uptime_seconds": int(psutil.boot_time()),
    }


@app.get("/v1/capabilities")
async def capabilities():
    """Report device capabilities and compatibility metadata."""
    identity = _sim_identity()
    disk = shutil.disk_usage("/")
    mem = psutil.virtual_memory()

    return {
        "agent_version": AGENT_VERSION,
        "hardware": {
            "model": os.environ.get("THOR_SIM_MODEL", identity.get("model", "Unknown")),
            "serial": os.environ.get("THOR_SIM_SERIAL", identity.get("serial", "unknown")),
            "architecture": platform.machine(),
            "cpu_count": psutil.cpu_count(),
            "memory_total_mb": mem.total // (1024 * 1024),
        },
        "os": {
            "system": platform.system(),
            "release": platform.release(),
            "version": platform.version(),
            "distro": _get_distro(),
        },
        "jetpack_version": os.environ.get("THOR_SIM_JETPACK", identity.get("jetpack")),
        "docker_version": _detect_docker(),
        "ros2_available": _detect_ros2(),
        "gpu": _detect_gpu(),
        "disk": {
            "total_gb": round(disk.total / (1024**3), 1),
            "free_gb": round(disk.free / (1024**3), 1),
        },
    }


@app.get("/v1/metrics")
async def metrics():
    """Current system metrics."""
    mem = psutil.virtual_memory()
    disk = shutil.disk_usage("/")
    temps = {}

    try:
        for name, entries in psutil.sensors_temperatures().items():
            for entry in entries:
                temps[f"{name}/{entry.label or 'main'}"] = entry.current
    except (AttributeError, RuntimeError):
        pass

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "cpu": {
            "percent": psutil.cpu_percent(interval=0.5),
            "per_cpu": psutil.cpu_percent(interval=0, percpu=True),
            "load_avg": list(os.getloadavg()),
        },
        "memory": {
            "total_mb": mem.total // (1024 * 1024),
            "used_mb": mem.used // (1024 * 1024),
            "percent": mem.percent,
        },
        "disk": {
            "total_gb": round(disk.total / (1024**3), 1),
            "used_gb": round(disk.used / (1024**3), 1),
            "percent": round(disk.used / disk.total * 100, 1),
        },
        "temperatures": temps,
        "network": _network_stats(),
    }


@app.post("/v1/exec")
async def exec_command(payload: dict):
    """Execute a command on the device (guarded)."""
    command = payload.get("command", "")
    timeout = payload.get("timeout", 30)

    if not command:
        return JSONResponse(
            status_code=400,
            content={"error": "command is required"}
        )

    # Block dangerous commands
    dangerous = ["rm -rf /", "mkfs", "dd if=", "shutdown", "reboot", "halt"]
    for d in dangerous:
        if d in command:
            return JSONResponse(
                status_code=403,
                content={"error": f"Blocked dangerous command pattern: {d}"}
            )

    try:
        result = subprocess.run(
            command, shell=True,
            capture_output=True, text=True,
            timeout=timeout
        )
        return {
            "exit_code": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr,
        }
    except subprocess.TimeoutExpired:
        return JSONResponse(
            status_code=408,
            content={"error": f"Command timed out after {timeout}s"}
        )


# ── Docker Management ──────────────────────────────────────────────────

@app.get("/v1/docker/containers")
async def docker_containers():
    """List Docker containers."""
    try:
        result = subprocess.run(
            ["docker", "ps", "-a", "--format",
             '{"id":"{{.ID}}","name":"{{.Names}}","image":"{{.Image}}",'
             '"status":"{{.Status}}","state":"{{.State}}","ports":"{{.Ports}}"}'],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0:
            return {"containers": [], "error": result.stderr.strip()}

        containers = []
        for line in result.stdout.strip().split("\n"):
            if line:
                containers.append(json.loads(line))
        return {"containers": containers}
    except FileNotFoundError:
        return {"containers": [], "error": "Docker not installed"}
    except subprocess.TimeoutExpired:
        return {"containers": [], "error": "Docker command timed out"}


@app.post("/v1/docker/action")
async def docker_action(payload: dict):
    """Start, stop, restart, or remove a container."""
    container = payload.get("container", "")
    action = payload.get("action", "")

    if not container or action not in ("start", "stop", "restart", "remove"):
        return JSONResponse(
            status_code=400,
            content={"error": "container and action (start|stop|restart|remove) required"}
        )

    cmd = ["docker", action, container]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return {
            "action": action,
            "container": container,
            "exit_code": result.returncode,
            "stdout": result.stdout.strip(),
            "stderr": result.stderr.strip(),
        }
    except subprocess.TimeoutExpired:
        return JSONResponse(status_code=408, content={"error": "Timed out"})


@app.get("/v1/docker/logs/{container}")
async def docker_logs(container: str, tail: int = 100):
    """Get container logs."""
    try:
        result = subprocess.run(
            ["docker", "logs", "--tail", str(tail), "--timestamps", container],
            capture_output=True, text=True, timeout=10
        )
        return {
            "container": container,
            "logs": result.stdout,
            "stderr": result.stderr,
        }
    except FileNotFoundError:
        return {"container": container, "logs": "", "error": "Docker not installed"}


# ── Log Streaming ──────────────────────────────────────────────────────

@app.get("/v1/logs/system")
async def system_logs(lines: int = 100, unit: str = ""):
    """Get system journal logs."""
    cmd = ["journalctl", "--no-pager", "-n", str(lines), "--output", "short-iso"]
    if unit:
        cmd += ["-u", unit]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return {
            "source": unit or "system",
            "lines": result.stdout.strip().split("\n") if result.stdout.strip() else [],
            "count": len(result.stdout.strip().split("\n")) if result.stdout.strip() else 0,
        }
    except FileNotFoundError:
        return {"source": unit or "system", "lines": [], "error": "journalctl not available"}


@app.get("/v1/logs/agent")
async def agent_logs(lines: int = 50):
    """Get THOR agent logs (last N lines from stdout)."""
    # In production, this reads from journalctl -u thor-agent
    # In sim mode, return a placeholder
    return {
        "source": "thor-agent",
        "lines": [f"[THOR Agent] Running on 127.0.0.1:8470 — agent v{AGENT_VERSION}"],
        "count": 1,
    }


# ── Services ───────────────────────────────────────────────────────────

@app.get("/v1/services")
async def list_services():
    """List systemd services (filtered to interesting ones)."""
    try:
        result = subprocess.run(
            ["systemctl", "list-units", "--type=service", "--state=running",
             "--no-pager", "--plain", "--no-legend"],
            capture_output=True, text=True, timeout=10
        )
        services = []
        for line in result.stdout.strip().split("\n"):
            parts = line.split()
            if len(parts) >= 4:
                services.append({
                    "name": parts[0],
                    "load": parts[1],
                    "active": parts[2],
                    "sub": parts[3],
                })
        return {"services": services}
    except FileNotFoundError:
        return {"services": [], "error": "systemctl not available"}


# ── ANIMA Module Management ────────────────────────────────────────────

ANIMA_MODULES_DIR = os.environ.get("ANIMA_MODULES_DIR", "/opt/anima/modules")
ANIMA_PIPELINES_DIR = os.environ.get("ANIMA_PIPELINES_DIR", "/opt/anima/pipelines")


@app.get("/v1/anima/modules")
async def anima_modules():
    """List available ANIMA modules by scanning for anima_module.yaml manifests."""
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
                    # Flatten nested structure for Swift consumption
                    module_info = _flatten_manifest(manifest, entry)
                    modules.append(module_info)
                except Exception as e:
                    modules.append({"name": entry, "error": str(e)})

    # If no real modules found, return simulated ones for development
    if not modules:
        modules = _simulated_modules()

    return {"modules": modules, "count": len(modules)}


@app.post("/v1/anima/deploy")
async def anima_deploy(payload: dict):
    """Deploy an ANIMA pipeline from docker-compose YAML."""
    compose_yaml = payload.get("compose_yaml", "")
    pipeline_name = payload.get("pipeline_name", "default")

    if not compose_yaml:
        return JSONResponse(status_code=400, content={"error": "compose_yaml is required"})

    os.makedirs(ANIMA_PIPELINES_DIR, exist_ok=True)
    compose_path = os.path.join(ANIMA_PIPELINES_DIR, f"{pipeline_name}.yaml")

    # Write compose file
    with open(compose_path, "w") as f:
        f.write(compose_yaml)

    # Deploy with docker compose
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


@app.get("/v1/anima/status")
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
                        ["docker", "compose", "-f", compose_path, "-p", f"anima-{pipeline_name}", "ps",
                         "--format", "json"],
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
                        "name": pipeline_name,
                        "compose_path": compose_path,
                        "containers": containers,
                        "status": "running" if containers else "stopped",
                    })
                except (subprocess.TimeoutExpired, FileNotFoundError):
                    pipelines.append({
                        "name": pipeline_name,
                        "status": "unknown",
                        "error": "Could not query status",
                    })

    return {"pipelines": pipelines}


@app.post("/v1/anima/stop")
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
        return {
            "status": "stopped" if result.returncode == 0 else "failed",
            "pipeline": pipeline_name,
            "exit_code": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr,
        }
    except subprocess.TimeoutExpired:
        return JSONResponse(status_code=408, content={"error": "Stop timed out"})


# ── ROS2 Introspection ────────────────────────────────────────────────

@app.get("/v1/ros2/nodes")
async def ros2_nodes():
    """List ROS2 nodes."""
    try:
        result = subprocess.run(["ros2", "node", "list"], capture_output=True, text=True, timeout=10)
        nodes = [n.strip() for n in result.stdout.strip().split("\n") if n.strip()]
        return {"nodes": nodes, "count": len(nodes)}
    except FileNotFoundError:
        return {"nodes": [], "count": 0, "error": "ROS2 not installed"}


@app.get("/v1/ros2/topics")
async def ros2_topics():
    """List ROS2 topics with types."""
    try:
        result = subprocess.run(["ros2", "topic", "list", "-t"], capture_output=True, text=True, timeout=10)
        topics = []
        for line in result.stdout.strip().split("\n"):
            if line.strip():
                parts = line.strip().split(" [")
                name = parts[0].strip()
                msg_type = parts[1].rstrip("]") if len(parts) > 1 else "unknown"
                topics.append({"name": name, "type": msg_type})
        return {"topics": topics, "count": len(topics)}
    except FileNotFoundError:
        return {"topics": [], "count": 0, "error": "ROS2 not installed"}


@app.get("/v1/ros2/services")
async def ros2_services():
    """List ROS2 services with types."""
    try:
        result = subprocess.run(["ros2", "service", "list", "-t"], capture_output=True, text=True, timeout=10)
        services = []
        for line in result.stdout.strip().split("\n"):
            if line.strip():
                parts = line.strip().split(" [")
                name = parts[0].strip()
                srv_type = parts[1].rstrip("]") if len(parts) > 1 else "unknown"
                services.append({"name": name, "type": srv_type})
        return {"services": services, "count": len(services)}
    except FileNotFoundError:
        return {"services": [], "count": 0, "error": "ROS2 not installed"}


# ── System Management ─────────────────────────────────────────────────

@app.post("/v1/system/reboot")
async def system_reboot(payload: dict):
    """Reboot the device (requires confirmation token)."""
    confirm = payload.get("confirm", "")
    if confirm != "REBOOT_CONFIRMED":
        return JSONResponse(
            status_code=400,
            content={"error": "Must send confirm='REBOOT_CONFIRMED' to reboot"}
        )
    try:
        subprocess.Popen(["sudo", "reboot"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return {"status": "rebooting", "message": "Device will reboot momentarily"}
    except Exception as e:
        return JSONResponse(status_code=500, content={"error": str(e)})


# ── ANIMA Helpers ──────────────────────────────────────────────────────

def _flatten_manifest(manifest: dict, fallback_name: str) -> dict:
    """Flatten anima_module.yaml structure into a flat JSON for the Swift client."""
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
        "capabilities": [
            {"type": c.get("type", ""), "subtype": c.get("subtype")}
            for c in manifest.get("capabilities", {}).get("provides", [])
        ],
        "inputs": [
            {"name": i.get("name", ""), "ros2_type": i.get("ros2_type", ""), "encoding": i.get("encoding"), "min_hz": i.get("min_hz")}
            for i in interface.get("inputs", [])
        ],
        "outputs": [
            {"name": o.get("name", ""), "ros2_type": o.get("ros2_type", ""), "typical_hz": o.get("typical_hz")}
            for o in interface.get("outputs", [])
        ],
        "hardware_platforms": [
            {"name": p.get("name", ""), "backends": p.get("backends", [])}
            for p in hardware.get("platforms", [])
        ],
        "performance_profiles": [
            {
                "platform": p.get("platform", ""),
                "model": p.get("model"),
                "backend": p.get("backend", ""),
                "fps": p.get("fps"),
                "latency_p50_ms": p.get("latency_p50_ms"),
                "memory_mb": p.get("memory_mb"),
            }
            for p in performance.get("profiles", [])
        ],
        "failure_mode": safety.get("failure_mode"),
        "timeout_ms": safety.get("timeout_ms"),
        "health_topic": safety.get("health_topic"),
    }


def _simulated_modules() -> list:
    """Return simulated ANIMA modules for development/testing."""
    return [
        {
            "schema_version": "1.0",
            "name": "petra",
            "version": "0.1.0",
            "display_name": "PETRA",
            "description": "Foundation depth perception model",
            "category": "perception.depth",
            "container_image": "ghcr.io/aiflowlabs/anima-petra:0.1.0",
            "capabilities": [{"type": "depth_prediction", "subtype": "relative_depth"}],
            "inputs": [{"name": "depth_image", "ros2_type": "sensor_msgs/msg/Image", "encoding": ["32FC1"], "min_hz": 1}],
            "outputs": [{"name": "features", "ros2_type": "std_msgs/msg/Float32MultiArray", "typical_hz": 10}],
            "hardware_platforms": [{"name": "jetson", "backends": ["tensorrt", "cuda"]}],
            "performance_profiles": [{"platform": "jetson_tensorrt", "model": "petra-25m", "backend": "tensorrt", "fps": 30, "latency_p50_ms": 35, "memory_mb": 512}],
            "failure_mode": "returns_empty",
            "timeout_ms": 5000,
            "health_topic": "/anima/petra/health",
        },
        {
            "schema_version": "1.0",
            "name": "chronos",
            "version": "0.1.0",
            "display_name": "CHRONOS",
            "description": "Multi-object tracking and temporal reasoning",
            "category": "perception.tracking",
            "container_image": "ghcr.io/aiflowlabs/anima-chronos:0.1.0",
            "capabilities": [{"type": "object_tracking", "subtype": "multi_object"}],
            "inputs": [{"name": "detections", "ros2_type": "vision_msgs/msg/Detection2DArray", "encoding": None, "min_hz": 5}],
            "outputs": [{"name": "tracks", "ros2_type": "vision_msgs/msg/Detection2DArray", "typical_hz": 15}],
            "hardware_platforms": [{"name": "jetson", "backends": ["tensorrt", "cuda"]}, {"name": "linux_x86", "backends": ["cuda", "cpu"]}],
            "performance_profiles": [{"platform": "jetson_tensorrt", "model": "chronos-s", "backend": "tensorrt", "fps": 25, "latency_p50_ms": 40, "memory_mb": 384}],
            "failure_mode": "returns_empty",
            "timeout_ms": 3000,
            "health_topic": "/anima/chronos/health",
        },
        {
            "schema_version": "1.0",
            "name": "pygmalion",
            "version": "0.1.0",
            "display_name": "PYGMALION",
            "description": "Vision-Language-Action model for robot control",
            "category": "action.vla",
            "container_image": "ghcr.io/aiflowlabs/anima-pygmalion:0.1.0",
            "capabilities": [{"type": "vision_language_action", "subtype": "smolvla"}],
            "inputs": [
                {"name": "camera", "ros2_type": "sensor_msgs/msg/Image", "encoding": ["rgb8"], "min_hz": 5},
                {"name": "robot_state", "ros2_type": "sensor_msgs/msg/JointState", "encoding": None, "min_hz": 10},
            ],
            "outputs": [{"name": "action", "ros2_type": "std_msgs/msg/Float32MultiArray", "typical_hz": 10}],
            "hardware_platforms": [{"name": "jetson", "backends": ["tensorrt", "cuda"]}],
            "performance_profiles": [{"platform": "jetson_tensorrt", "model": "smolvla-base", "backend": "tensorrt", "fps": 10, "latency_p50_ms": 100, "memory_mb": 2048}],
            "failure_mode": "hold_last",
            "timeout_ms": 10000,
            "health_topic": "/anima/pygmalion/health",
        },
    ]


def _get_distro() -> str:
    """Get Linux distribution info."""
    try:
        with open("/etc/os-release") as f:
            for line in f:
                if line.startswith("PRETTY_NAME="):
                    return line.split("=", 1)[1].strip().strip('"')
    except FileNotFoundError:
        pass
    return f"{platform.system()} {platform.release()}"


def _detect_gpu() -> dict:
    """Detect GPU info (NVIDIA specific)."""
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,memory.total,memory.used,temperature.gpu",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            parts = result.stdout.strip().split(", ")
            return {
                "name": parts[0] if len(parts) > 0 else "Unknown",
                "memory_total_mb": int(parts[1]) if len(parts) > 1 else 0,
                "memory_used_mb": int(parts[2]) if len(parts) > 2 else 0,
                "temperature_c": float(parts[3]) if len(parts) > 3 else 0,
            }
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return {"name": "N/A (simulated)", "memory_total_mb": 0, "memory_used_mb": 0, "temperature_c": 0}


def _network_stats() -> dict:
    """Get network interface stats."""
    counters = psutil.net_io_counters()
    return {
        "bytes_sent": counters.bytes_sent,
        "bytes_recv": counters.bytes_recv,
    }


if __name__ == "__main__":
    host = os.environ.get("THOR_AGENT_HOST", "127.0.0.1")
    port = int(os.environ.get("THOR_AGENT_PORT", "8470"))
    print(f"[THOR Agent] Starting on {host}:{port}")
    uvicorn.run(app, host=host, port=port, log_level="info")
