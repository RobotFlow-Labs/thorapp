"""Power management: nvpmodel, jetson_clocks, fan control, thermal."""

import subprocess
from fastapi import APIRouter
from fastapi.responses import JSONResponse
from sim import is_sim, get_sim_state, set_sim_state

router = APIRouter(prefix="/v1/power", tags=["power"])


@router.get("/mode")
async def get_power_mode():
    """Get current power mode and available modes."""
    if is_sim():
        return {
            "current_mode": get_sim_state("power_mode", 0),
            "modes": [
                {"id": 0, "name": "MAXN", "description": "Maximum performance, all cores active"},
                {"id": 1, "name": "30W", "description": "30W power budget"},
                {"id": 2, "name": "15W", "description": "15W power budget"},
            ],
        }
    try:
        result = subprocess.run(["nvpmodel", "-q"], capture_output=True, text=True, timeout=5)
        current = 0
        for line in result.stdout.split("\n"):
            if "NV Power Mode" in line:
                parts = line.split(":")
                if len(parts) > 1:
                    current = int(parts[1].strip().split()[0]) if parts[1].strip() else 0

        list_result = subprocess.run(["nvpmodel", "-l"], capture_output=True, text=True, timeout=5)
        modes = []
        for line in list_result.stdout.split("\n"):
            if line.strip().startswith("POWER_MODEL"):
                parts = line.split()
                modes.append({"id": len(modes), "name": parts[-1] if parts else str(len(modes)), "description": line.strip()})

        return {"current_mode": current, "modes": modes if modes else [{"id": 0, "name": "DEFAULT", "description": "Default mode"}]}
    except FileNotFoundError:
        return {"current_mode": 0, "modes": [], "error": "nvpmodel not installed"}


@router.post("/mode")
async def set_power_mode(payload: dict):
    """Set power mode."""
    mode = payload.get("mode", 0)
    if is_sim():
        set_sim_state("power_mode", mode)
        return {"current_mode": mode, "status": "ok"}
    try:
        result = subprocess.run(["sudo", "nvpmodel", "-m", str(mode)], capture_output=True, text=True, timeout=10)
        return {"current_mode": mode, "status": "ok" if result.returncode == 0 else "error", "stderr": result.stderr}
    except FileNotFoundError:
        return JSONResponse(status_code=400, content={"error": "nvpmodel not installed"})


@router.get("/clocks")
async def get_clocks():
    """Get jetson_clocks status."""
    if is_sim():
        return {"enabled": get_sim_state("clocks_enabled", False), "details": "Simulated clock state"}
    try:
        result = subprocess.run(["jetson_clocks", "--show"], capture_output=True, text=True, timeout=5)
        enabled = "SOC family" in result.stdout  # jetson_clocks --show outputs clock info when active
        return {"enabled": enabled, "details": result.stdout[:500]}
    except FileNotFoundError:
        return {"enabled": False, "details": None, "error": "jetson_clocks not installed"}


@router.post("/clocks")
async def set_clocks(payload: dict):
    """Enable or disable jetson_clocks."""
    enable = payload.get("enable", True)
    if is_sim():
        set_sim_state("clocks_enabled", enable)
        return {"enabled": enable, "status": "ok"}
    try:
        cmd = ["sudo", "jetson_clocks"] if enable else ["sudo", "jetson_clocks", "--restore"]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return {"enabled": enable, "status": "ok" if result.returncode == 0 else "error", "stderr": result.stderr}
    except FileNotFoundError:
        return JSONResponse(status_code=400, content={"error": "jetson_clocks not installed"})


@router.get("/fan")
async def get_fan():
    """Get fan status."""
    if is_sim():
        speed = get_sim_state("fan_speed", 128)
        return {"target_pwm": speed, "current_pwm": speed, "speed_percent": round(speed / 255 * 100, 1)}
    try:
        target = int(open("/sys/devices/pwm-fan/target_pwm").read().strip())
        current = int(open("/sys/devices/pwm-fan/cur_pwm").read().strip())
        return {"target_pwm": target, "current_pwm": current, "speed_percent": round(current / 255 * 100, 1)}
    except (FileNotFoundError, ValueError):
        return {"target_pwm": 0, "current_pwm": 0, "speed_percent": 0, "error": "Fan control not available"}


@router.post("/fan")
async def set_fan(payload: dict):
    """Set fan speed (0-255 PWM)."""
    speed = max(0, min(255, payload.get("speed", 128)))
    if is_sim():
        set_sim_state("fan_speed", speed)
        return {"target_pwm": speed, "speed_percent": round(speed / 255 * 100, 1), "status": "ok"}
    try:
        with open("/sys/devices/pwm-fan/target_pwm", "w") as f:
            f.write(str(speed))
        return {"target_pwm": speed, "speed_percent": round(speed / 255 * 100, 1), "status": "ok"}
    except (FileNotFoundError, PermissionError) as e:
        return JSONResponse(status_code=400, content={"error": str(e)})
