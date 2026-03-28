"""System info, packages, users."""

import os
import platform
import subprocess
from datetime import datetime, timezone
from fastapi import APIRouter
from sim import is_sim, sim_identity, get_distro

router = APIRouter(prefix="/v1/system", tags=["system"])


@router.get("/info")
async def system_info():
    """Get comprehensive system information."""
    identity = sim_identity()

    # Read tegra release
    tegra_release = None
    try:
        with open("/etc/nv_tegra_release") as f:
            tegra_release = f.read().strip()
    except FileNotFoundError:
        pass

    # Read device tree model
    model = os.environ.get("THOR_SIM_MODEL", identity.get("model", "Unknown"))
    try:
        with open("/proc/device-tree/model") as f:
            model = f.read().strip().rstrip("\x00")
    except FileNotFoundError:
        pass

    # Uptime
    try:
        with open("/proc/uptime") as f:
            uptime_secs = float(f.read().split()[0])
            hours = int(uptime_secs // 3600)
            mins = int((uptime_secs % 3600) // 60)
            uptime = f"{hours}h {mins}m"
    except (FileNotFoundError, ValueError):
        uptime = "unknown"

    return {
        "kernel": platform.release(),
        "kernel_version": platform.version(),
        "architecture": platform.machine(),
        "hostname": platform.node(),
        "os_release": get_distro(),
        "model": model,
        "tegra_release": tegra_release,
        "l4t_version": identity.get("jetpack"),
        "uptime": uptime,
        "python_version": platform.python_version(),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/packages")
async def list_packages():
    """List installed packages (top 100)."""
    try:
        result = subprocess.run(
            ["dpkg", "-l", "--no-pager"],
            capture_output=True, text=True, timeout=10
        )
        packages = []
        for line in result.stdout.split("\n"):
            if line.startswith("ii"):
                parts = line.split()
                if len(parts) >= 3:
                    packages.append({
                        "name": parts[1],
                        "version": parts[2],
                        "description": " ".join(parts[4:]) if len(parts) > 4 else "",
                    })
        return {"packages": packages[:200], "total": len(packages)}
    except FileNotFoundError:
        return {"packages": [], "total": 0, "error": "dpkg not available"}


@router.post("/packages")
async def package_action(payload: dict):
    """Run apt update or upgrade."""
    action = payload.get("action", "update")
    if action not in ("update", "upgrade"):
        return {"error": f"Invalid action: {action}. Use 'update' or 'upgrade'."}
    try:
        cmd = ["sudo", "apt", "-y", action] if action == "upgrade" else ["sudo", "apt", action]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        return {
            "action": action,
            "exit_code": result.returncode,
            "stdout": result.stdout[-1000:],  # last 1000 chars
            "stderr": result.stderr[-500:],
        }
    except subprocess.TimeoutExpired:
        return {"action": action, "error": "Timed out after 300s"}


@router.get("/users")
async def list_users():
    """List system users (UID >= 1000)."""
    users = []
    try:
        with open("/etc/passwd") as f:
            for line in f:
                parts = line.strip().split(":")
                if len(parts) >= 7:
                    uid = int(parts[2])
                    if uid >= 1000 and uid < 65534:
                        users.append({
                            "name": parts[0],
                            "uid": uid,
                            "gid": int(parts[3]),
                            "home": parts[5],
                            "shell": parts[6],
                        })
    except FileNotFoundError:
        pass
    return {"users": users}


@router.post("/reboot")
async def system_reboot(payload: dict):
    """Reboot the device (requires confirmation token)."""
    confirm = payload.get("confirm", "")
    if confirm != "REBOOT_CONFIRMED":
        return {"error": "Must send confirm='REBOOT_CONFIRMED' to reboot"}
    try:
        subprocess.Popen(["sudo", "reboot"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return {"status": "rebooting", "message": "Device will reboot momentarily"}
    except Exception as e:
        return {"error": str(e)}
