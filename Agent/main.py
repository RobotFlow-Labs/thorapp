"""
THOR Jetson Agent — localhost-only HTTP/JSON API.

Runs as a systemd service on the Jetson device.
Bound to 127.0.0.1 only (accessed via SSH tunnel from Mac).

50+ endpoints organized by router:
  /v1/health, /v1/capabilities, /v1/metrics  — core
  /v1/power/*                                 — nvpmodel, clocks, fan
  /v1/system/*                                — info, packages, users, reboot
  /v1/storage/*                               — disks, swap
  /v1/network/*                               — interfaces, wifi
  /v1/hardware/*                              — cameras, GPIO, I2C, USB, serial
  /v1/docker/*                                — containers, images, logs
  /v1/ros2/*                                  — nodes, topics, launch, lifecycle, bags
  /v1/gpu/*, /v1/models/*                     — CUDA, TensorRT, model management
  /v1/logs/*                                  — system, agent logs
  /v1/anima/*                                 — module management, pipeline deployment
"""

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

# Add parent dir to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from sim import sim_identity, get_distro
from routers import power, system, storage, network, hardware, ros2, gpu, docker, logs, anima

AGENT_VERSION = "0.1.0"

app = FastAPI(title="THOR Jetson Agent", version=AGENT_VERSION)

# Register all routers
app.include_router(power.router)
app.include_router(system.router)
app.include_router(storage.router)
app.include_router(network.router)
app.include_router(hardware.router)
app.include_router(ros2.router)
app.include_router(gpu.router)
app.include_router(docker.router)
app.include_router(logs.router)
app.include_router(anima.router)


# ── Core Endpoints ─────────────────────────────────────────────────────

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
    identity = sim_identity()
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
            "distro": get_distro(),
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
        "network": {
            "bytes_sent": psutil.net_io_counters().bytes_sent,
            "bytes_recv": psutil.net_io_counters().bytes_recv,
        },
    }


@app.post("/v1/exec")
async def exec_command(payload: dict):
    """Execute a command on the device (guarded)."""
    command = payload.get("command", "")
    timeout = payload.get("timeout", 30)

    if not command:
        return JSONResponse(status_code=400, content={"error": "command is required"})

    dangerous = ["rm -rf /", "mkfs", "dd if=", "shutdown", "halt"]
    for d in dangerous:
        if d in command:
            return JSONResponse(status_code=403, content={"error": f"Blocked dangerous command pattern: {d}"})

    try:
        result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=timeout)
        return {"exit_code": result.returncode, "stdout": result.stdout, "stderr": result.stderr}
    except subprocess.TimeoutExpired:
        return JSONResponse(status_code=408, content={"error": f"Command timed out after {timeout}s"})


@app.get("/v1/services")
async def list_services():
    """List systemd services."""
    try:
        result = subprocess.run(
            ["systemctl", "list-units", "--type=service", "--state=running", "--no-pager", "--plain", "--no-legend"],
            capture_output=True, text=True, timeout=10
        )
        services = []
        for line in result.stdout.strip().split("\n"):
            parts = line.split()
            if len(parts) >= 4:
                services.append({"name": parts[0], "load": parts[1], "active": parts[2], "sub": parts[3]})
        return {"services": services}
    except FileNotFoundError:
        return {"services": [], "error": "systemctl not available"}


# ── Helpers ────────────────────────────────────────────────────────────

def _detect_docker():
    try:
        result = subprocess.run(["docker", "--version"], capture_output=True, text=True, timeout=5)
        if result.returncode == 0:
            return result.stdout.strip()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return None


def _detect_ros2():
    try:
        result = subprocess.run(["ros2", "--version"], capture_output=True, text=True, timeout=5)
        return result.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def _detect_gpu():
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,memory.total,memory.used,temperature.gpu", "--format=csv,noheader,nounits"],
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


if __name__ == "__main__":
    host = os.environ.get("THOR_AGENT_HOST", "127.0.0.1")
    port = int(os.environ.get("THOR_AGENT_PORT", "8470"))
    print(f"[THOR Agent] Starting on {host}:{port}")
    print(f"[THOR Agent] Version: {AGENT_VERSION}")
    print(f"[THOR Agent] Routers: power, system, storage, network, hardware, ros2, gpu, docker, logs, anima")
    uvicorn.run(app, host=host, port=port, log_level="info")
