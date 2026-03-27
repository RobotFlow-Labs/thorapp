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
