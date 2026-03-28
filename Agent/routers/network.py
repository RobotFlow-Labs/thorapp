"""Network management: interfaces, WiFi."""

import json
import subprocess
from fastapi import APIRouter

router = APIRouter(prefix="/v1/network", tags=["network"])


@router.get("/interfaces")
async def network_interfaces():
    """List network interfaces with IP addresses."""
    try:
        result = subprocess.run(["ip", "-j", "addr", "show"], capture_output=True, text=True, timeout=5)
        if result.returncode == 0:
            interfaces = json.loads(result.stdout)
            # Simplify output
            simplified = []
            for iface in interfaces:
                addrs = []
                for addr_info in iface.get("addr_info", []):
                    addrs.append({
                        "family": addr_info.get("family"),
                        "address": addr_info.get("local"),
                        "prefix": addr_info.get("prefixlen"),
                    })
                simplified.append({
                    "name": iface.get("ifname"),
                    "state": iface.get("operstate"),
                    "mac": iface.get("address"),
                    "mtu": iface.get("mtu"),
                    "addresses": addrs,
                })
            return {"interfaces": simplified}
    except (FileNotFoundError, json.JSONDecodeError):
        pass

    # Fallback
    try:
        result = subprocess.run(["ifconfig"], capture_output=True, text=True, timeout=5)
        return {"interfaces": [], "raw": result.stdout, "error": "ip command not available, using ifconfig fallback"}
    except FileNotFoundError:
        return {"interfaces": [], "error": "Neither ip nor ifconfig available"}


@router.get("/wifi")
async def wifi_list():
    """List available WiFi networks."""
    try:
        result = subprocess.run(
            ["nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY,CHAN,FREQ", "device", "wifi", "list"],
            capture_output=True, text=True, timeout=10
        )
        networks = []
        for line in result.stdout.strip().split("\n"):
            if line.strip():
                parts = line.split(":")
                if len(parts) >= 3 and parts[0]:
                    networks.append({
                        "ssid": parts[0],
                        "signal": int(parts[1]) if parts[1].isdigit() else 0,
                        "security": parts[2],
                        "channel": parts[3] if len(parts) > 3 else "",
                        "frequency": parts[4] if len(parts) > 4 else "",
                    })
        return {"networks": networks}
    except FileNotFoundError:
        return {"networks": [], "error": "nmcli not installed"}


@router.post("/wifi")
async def wifi_connect(payload: dict):
    """Connect to a WiFi network."""
    ssid = payload.get("ssid", "")
    password = payload.get("password", "")

    if not ssid:
        return {"error": "ssid is required"}
    try:
        cmd = ["nmcli", "device", "wifi", "connect", ssid]
        if password:
            cmd += ["password", password]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return {
            "success": result.returncode == 0,
            "ssid": ssid,
            "stdout": result.stdout,
            "error": result.stderr if result.returncode != 0 else None,
        }
    except FileNotFoundError:
        return {"success": False, "error": "nmcli not installed"}
