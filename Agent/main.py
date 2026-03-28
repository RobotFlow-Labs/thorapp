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
