"""Storage management: disks, NVMe health, swap."""

import json
import subprocess
from fastapi import APIRouter

router = APIRouter(prefix="/v1/storage", tags=["storage"])


@router.get("/disks")
async def disk_info():
    """Get disk and filesystem information."""
    # Block devices
    block_devices = []
    try:
        result = subprocess.run(["lsblk", "-J", "-o", "NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE"], capture_output=True, text=True, timeout=5)
        if result.returncode == 0:
            data = json.loads(result.stdout)
            block_devices = data.get("blockdevices", [])
    except (FileNotFoundError, json.JSONDecodeError):
        pass

    # Filesystem usage
    filesystems = []
    try:
        result = subprocess.run(["df", "-h", "--output=source,fstype,size,used,avail,pcent,target"], capture_output=True, text=True, timeout=5)
        for line in result.stdout.strip().split("\n")[1:]:
            parts = line.split()
            if len(parts) >= 7 and not parts[0].startswith("tmpfs"):
                filesystems.append({
                    "source": parts[0],
                    "fstype": parts[1],
                    "size": parts[2],
                    "used": parts[3],
                    "available": parts[4],
                    "percent": parts[5],
                    "mount": parts[6],
                })
    except FileNotFoundError:
        pass

    # NVMe health
    nvme_health = None
    try:
        result = subprocess.run(["sudo", "smartctl", "-a", "/dev/nvme0n1"], capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            nvme_health = {"raw": result.stdout[:2000], "status": "ok"}
    except FileNotFoundError:
        pass

    return {
        "block_devices": block_devices,
        "filesystems": filesystems,
        "nvme_health": nvme_health,
    }


@router.get("/swap")
async def swap_info():
    """Get swap status."""
    try:
        result = subprocess.run(["free", "-h"], capture_output=True, text=True, timeout=5)
        swap_line = None
        for line in result.stdout.split("\n"):
            if line.startswith("Swap:"):
                parts = line.split()
                swap_line = {
                    "total": parts[1] if len(parts) > 1 else "0",
                    "used": parts[2] if len(parts) > 2 else "0",
                    "free": parts[3] if len(parts) > 3 else "0",
                }
        # Swap files
        swap_files = []
        try:
            sr = subprocess.run(["swapon", "--show", "--noheadings"], capture_output=True, text=True, timeout=5)
            for line in sr.stdout.strip().split("\n"):
                if line.strip():
                    parts = line.split()
                    swap_files.append({"name": parts[0], "type": parts[1] if len(parts) > 1 else "", "size": parts[2] if len(parts) > 2 else ""})
        except FileNotFoundError:
            pass

        return {"swap": swap_line, "swap_files": swap_files}
    except FileNotFoundError:
        return {"swap": None, "error": "free command not available"}


@router.post("/swap")
async def swap_action(payload: dict):
    """Enable or disable swap."""
    action = payload.get("action", "on")  # "on" or "off"
    file = payload.get("file", "/swapfile")

    cmd = ["sudo", "swapon", file] if action == "on" else ["sudo", "swapoff", file]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return {"action": action, "file": file, "exit_code": result.returncode, "stderr": result.stderr}
    except FileNotFoundError:
        return {"error": "swapon/swapoff not available"}
