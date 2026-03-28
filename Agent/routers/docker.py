"""Docker container management."""

import json
import subprocess
from fastapi import APIRouter
from fastapi.responses import JSONResponse

router = APIRouter(prefix="/v1/docker", tags=["docker"])


@router.get("/containers")
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


@router.post("/action")
async def docker_action(payload: dict):
    """Start, stop, restart, or remove a container."""
    container = payload.get("container", "")
    action = payload.get("action", "")
    if not container or action not in ("start", "stop", "restart", "remove"):
        return JSONResponse(status_code=400, content={"error": "container and action (start|stop|restart|remove) required"})
    try:
        result = subprocess.run(["docker", action, container], capture_output=True, text=True, timeout=30)
        return {"action": action, "container": container, "exit_code": result.returncode, "stdout": result.stdout.strip(), "stderr": result.stderr.strip()}
    except subprocess.TimeoutExpired:
        return JSONResponse(status_code=408, content={"error": "Timed out"})


@router.get("/logs/{container}")
async def docker_logs(container: str, tail: int = 100):
    """Get container logs."""
    try:
        result = subprocess.run(["docker", "logs", "--tail", str(tail), "--timestamps", container], capture_output=True, text=True, timeout=10)
        return {"container": container, "logs": result.stdout, "stderr": result.stderr}
    except FileNotFoundError:
        return {"container": container, "logs": "", "error": "Docker not installed"}


@router.get("/images")
async def docker_images():
    """List Docker images."""
    try:
        result = subprocess.run(
            ["docker", "images", "--format", '{"repository":"{{.Repository}}","tag":"{{.Tag}}","id":"{{.ID}}","size":"{{.Size}}","created":"{{.CreatedSince}}"}'],
            capture_output=True, text=True, timeout=10
        )
        images = []
        for line in result.stdout.strip().split("\n"):
            if line:
                images.append(json.loads(line))
        return {"images": images}
    except FileNotFoundError:
        return {"images": [], "error": "Docker not installed"}


@router.post("/pull")
async def docker_pull(payload: dict):
    """Pull a Docker image."""
    image = payload.get("image", "")
    if not image:
        return JSONResponse(status_code=400, content={"error": "image required"})
    try:
        result = subprocess.run(["docker", "pull", image], capture_output=True, text=True, timeout=600)
        return {"image": image, "exit_code": result.returncode, "stdout": result.stdout[-500:], "stderr": result.stderr[-500:]}
    except subprocess.TimeoutExpired:
        return JSONResponse(status_code=408, content={"error": "Pull timed out"})
