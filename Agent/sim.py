"""Simulation state and identity helpers for Docker-based Jetson sim."""

import json
import os
import platform


def is_sim() -> bool:
    """Check if running in simulation mode."""
    return os.path.exists("/etc/thor-sim/identity.json")


def sim_identity() -> dict:
    """Read simulated Jetson identity or detect real hardware."""
    identity_file = "/etc/thor-sim/identity.json"
    if os.path.exists(identity_file):
        with open(identity_file) as f:
            return json.load(f)

    model = "Unknown"
    jetpack = None

    model_file = "/proc/device-tree/model"
    if os.path.exists(model_file):
        with open(model_file) as f:
            model = f.read().strip().rstrip("\x00")

    jetpack_file = "/etc/nv_tegra_release"
    if os.path.exists(jetpack_file):
        with open(jetpack_file) as f:
            jetpack = f.read().strip()

    return {"model": model, "jetpack": jetpack}


def get_distro() -> str:
    """Get Linux distribution info."""
    try:
        with open("/etc/os-release") as f:
            for line in f:
                if line.startswith("PRETTY_NAME="):
                    return line.split("=", 1)[1].strip().strip('"')
    except FileNotFoundError:
        pass
    return f"{platform.system()} {platform.release()}"


# Mutable sim state for testing POST operations
_sim_state = {
    "power_mode": 0,
    "clocks_enabled": False,
    "fan_speed": 128,
}


def get_sim_state(key: str, default=None):
    return _sim_state.get(key, default)


def set_sim_state(key: str, value):
    _sim_state[key] = value
