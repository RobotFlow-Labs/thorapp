"""Hardware detection: cameras, GPIO, I2C, USB, serial ports."""

import binascii
import base64
import os
import subprocess
import time
from fastapi import APIRouter, HTTPException
from fastapi.responses import Response
from sim import active_camera_bridges, is_sim, set_sim_state, get_sim_state

router = APIRouter(prefix="/v1/hardware", tags=["hardware"])

MAX_BRIDGE_FRAME_BYTES = 2_000_000


def _bridged_camera_records():
    cameras = []
    for camera_id, bridge in active_camera_bridges(max_age_seconds=30).items():
        cameras.append({
            "name": bridge.get("name", "Bridged Camera"),
            "device": f"bridge:{camera_id}",
            "type": bridge.get("type", "USB"),
            "details": bridge.get("details", "Bridged from host macOS camera"),
            "source": "bridge",
            "bridge_state": "active",
            "preview_path": f"/v1/hardware/cameras/{camera_id}/snapshot",
            "width": bridge.get("width"),
            "height": bridge.get("height"),
            "fps": bridge.get("fps"),
            "last_frame_at": bridge.get("captured_at"),
        })
    return cameras


@router.get("/cameras")
async def list_cameras():
    """Detect connected cameras (CSI, USB, ZED)."""
    cameras = []

    # v4l2 cameras
    try:
        result = subprocess.run(["v4l2-ctl", "--list-devices"], capture_output=True, text=True, timeout=5)
        current_name = None
        for line in result.stdout.split("\n"):
            line = line.strip()
            if line and not line.startswith("/dev"):
                current_name = line.rstrip(":")
            elif line.startswith("/dev/video"):
                cameras.append({
                    "name": current_name or "Unknown Camera",
                    "device": line,
                    "type": "CSI" if "imx" in (current_name or "").lower() or "csi" in (current_name or "").lower() else "USB",
                })
    except FileNotFoundError:
        pass

    # Check for video devices directly
    if not cameras:
        for i in range(10):
            dev = f"/dev/video{i}"
            if os.path.exists(dev):
                cameras.append({"name": f"Video Device {i}", "device": dev, "type": "unknown"})

    # ZED camera detection
    try:
        result = subprocess.run(["lsusb"], capture_output=True, text=True, timeout=5)
        for line in result.stdout.split("\n"):
            if "2b03:" in line.lower() or "stereolabs" in line.lower():
                cameras.append({"name": "ZED Camera", "device": "USB", "type": "ZED", "details": line.strip()})
    except FileNotFoundError:
        pass

    if is_sim() and not cameras:
        cameras = [
            {"name": "Simulated CSI Camera", "device": "/dev/video0", "type": "CSI", "source": "simulated"},
            {"name": "Simulated USB Camera", "device": "/dev/video1", "type": "USB", "source": "simulated"},
        ]

    cameras.extend(_bridged_camera_records())

    return {"cameras": cameras, "count": len(cameras)}


@router.post("/camera-bridge/frame")
async def ingest_camera_bridge_frame(payload: dict):
    """Ingest a host-provided JPEG frame so the sim can expose a real camera source."""
    camera_id = str(payload.get("camera_id", "")).strip()
    name = str(payload.get("name", "")).strip()
    camera_type = str(payload.get("type", "USB")).strip() or "USB"
    captured_at = str(payload.get("captured_at", "")).strip()
    jpeg_base64 = payload.get("jpeg_base64", "")

    if not camera_id:
        raise HTTPException(status_code=400, detail="camera_id is required")
    if not name:
        raise HTTPException(status_code=400, detail="name is required")
    if not jpeg_base64 or not isinstance(jpeg_base64, str):
        raise HTTPException(status_code=400, detail="jpeg_base64 is required")

    try:
        frame_bytes = base64.b64decode(jpeg_base64, validate=True)
    except (ValueError, binascii.Error):
        raise HTTPException(status_code=400, detail="jpeg_base64 is not valid base64")

    if len(frame_bytes) > MAX_BRIDGE_FRAME_BYTES:
        raise HTTPException(status_code=413, detail="frame exceeds maximum accepted size")

    width = payload.get("width")
    height = payload.get("height")
    fps = payload.get("fps")

    bridges = dict(get_sim_state("camera_bridges", {}))
    bridges[camera_id] = {
        "name": name,
        "type": camera_type,
        "details": payload.get("details", "Bridged from host macOS camera"),
        "width": width,
        "height": height,
        "fps": fps,
        "captured_at": captured_at,
        "last_frame_time": time.time(),
        "frame_bytes": frame_bytes,
    }
    set_sim_state("camera_bridges", bridges)

    return {
        "status": "ok",
        "camera_id": camera_id,
        "bridge_state": "active",
        "preview_path": f"/v1/hardware/cameras/{camera_id}/snapshot",
    }


@router.delete("/camera-bridge/{camera_id}")
async def remove_camera_bridge(camera_id: str):
    bridges = dict(get_sim_state("camera_bridges", {}))
    removed = bridges.pop(camera_id, None)
    set_sim_state("camera_bridges", bridges)
    return {
        "status": "ok",
        "camera_id": camera_id,
        "bridge_state": "removed" if removed else "missing",
    }


@router.get("/cameras/{camera_id}/snapshot")
async def camera_snapshot(camera_id: str):
    bridge = active_camera_bridges(max_age_seconds=30).get(camera_id)
    if not bridge or not bridge.get("frame_bytes"):
        raise HTTPException(status_code=404, detail="snapshot not available")

    return Response(
        content=bridge["frame_bytes"],
        media_type="image/jpeg",
        headers={
            "Cache-Control": "no-store, max-age=0",
            "X-THOR-Camera-Bridge": "active",
        },
    )


@router.get("/gpio")
async def gpio_status():
    """Read GPIO pin states."""
    pins = []
    gpio_base = "/sys/class/gpio"

    if os.path.exists(gpio_base):
        for entry in sorted(os.listdir(gpio_base)):
            if entry.startswith("gpio") and entry[4:].isdigit():
                pin_path = os.path.join(gpio_base, entry)
                try:
                    direction = open(os.path.join(pin_path, "direction")).read().strip()
                    value = int(open(os.path.join(pin_path, "value")).read().strip())
                    pins.append({
                        "number": int(entry[4:]),
                        "direction": direction,
                        "value": value,
                    })
                except (FileNotFoundError, ValueError):
                    pass

    if is_sim() and not pins:
        pins = [
            {"number": 7, "direction": "out", "value": 0},
            {"number": 11, "direction": "in", "value": 1},
            {"number": 13, "direction": "out", "value": 1},
            {"number": 15, "direction": "in", "value": 0},
        ]

    return {"pins": pins, "count": len(pins)}


@router.get("/i2c")
async def i2c_scan():
    """Scan I2C buses for connected devices."""
    buses = []

    # Find I2C buses
    i2c_buses = []
    if os.path.exists("/dev"):
        for entry in os.listdir("/dev"):
            if entry.startswith("i2c-"):
                i2c_buses.append(int(entry.split("-")[1]))

    for bus_num in sorted(i2c_buses):
        devices = []
        try:
            result = subprocess.run(
                ["i2cdetect", "-y", "-r", str(bus_num)],
                capture_output=True, text=True, timeout=5
            )
            for line in result.stdout.split("\n")[1:]:
                parts = line.split(":")[1].strip().split() if ":" in line else []
                for addr_str in parts:
                    if addr_str != "--" and addr_str != "UU":
                        devices.append({"address": f"0x{addr_str}", "status": "detected"})
                    elif addr_str == "UU":
                        devices.append({"address": f"0x{addr_str}", "status": "in_use"})
        except FileNotFoundError:
            pass

        buses.append({"bus": bus_num, "devices": devices})

    if is_sim() and not buses:
        buses = [
            {"bus": 0, "devices": [{"address": "0x50", "status": "detected"}, {"address": "0x68", "status": "detected"}]},
            {"bus": 1, "devices": [{"address": "0x3c", "status": "detected"}]},
        ]

    return {"buses": buses}


@router.get("/usb")
async def usb_devices():
    """List USB devices."""
    devices = []
    try:
        result = subprocess.run(["lsusb"], capture_output=True, text=True, timeout=5)
        for line in result.stdout.strip().split("\n"):
            if line.strip():
                # Format: Bus 001 Device 002: ID 1234:5678 Description
                parts = line.split("ID ")
                bus_dev = line.split(":")[0] if ":" in line else ""
                desc = parts[1].split(" ", 1)[1] if len(parts) > 1 and " " in parts[1] else line
                vendor_product = parts[1].split(" ")[0] if len(parts) > 1 else ""
                devices.append({
                    "bus_device": bus_dev.strip(),
                    "vendor_product": vendor_product,
                    "description": desc.strip(),
                })
    except FileNotFoundError:
        if is_sim():
            devices = [
                {"bus_device": "Bus 001 Device 001", "vendor_product": "1d6b:0002", "description": "Linux Foundation 2.0 root hub"},
                {"bus_device": "Bus 001 Device 002", "vendor_product": "0bda:8153", "description": "Realtek USB 3.0 Ethernet"},
            ]
    return {"devices": devices, "count": len(devices)}


@router.get("/serial")
async def serial_ports():
    """List serial ports."""
    ports = []
    patterns = ["/dev/ttyUSB", "/dev/ttyACM", "/dev/ttyTHS", "/dev/ttyS"]

    for pattern in patterns:
        for i in range(10):
            path = f"{pattern}{i}"
            if os.path.exists(path):
                ports.append({"path": path, "type": pattern.split("/")[-1]})

    if is_sim() and not ports:
        ports = [{"path": "/dev/ttyTHS0", "type": "ttyTHS"}]

    return {"ports": ports, "count": len(ports)}
