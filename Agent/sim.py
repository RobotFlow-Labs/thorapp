"""Simulation state and identity helpers for Docker-based Jetson sim."""

import json
import os
import platform
import time
from datetime import datetime, timezone


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
    "registry_configs": {},
    "camera_bridges": {},
    "ros2_parameters": {
        "/camera_driver": {
            "exposure": {"type": "integer", "value": "42", "read_only": False},
            "frame_id": {"type": "string", "value": "zed_left_camera", "read_only": True},
        },
        "/scan_publisher": {
            "range_max": {"type": "double", "value": "12.0", "read_only": False},
            "frame_id": {"type": "string", "value": "laser", "read_only": True},
        },
    },
    "ros2_actions": [
        {
            "name": "/navigate_to_pose",
            "type": "nav2_msgs/action/NavigateToPose",
            "goal_schema": "{pose: {header: {frame_id: map}, pose: {position: {x: 0.0, y: 0.0}}}}",
        },
        {
            "name": "/dock_robot",
            "type": "example_interfaces/action/Fibonacci",
            "goal_schema": "{order: 5}",
        },
    ],
    "ros2_topic_stats": {
        "/camera/image_raw": {
            "message_type": "sensor_msgs/msg/Image",
            "publishers": 1,
            "subscribers": 2,
            "hz": 15.0,
            "bandwidth_bps": 2_400_000.0,
        },
        "/scan": {
            "message_type": "sensor_msgs/msg/LaserScan",
            "publishers": 1,
            "subscribers": 1,
            "hz": 10.0,
            "bandwidth_bps": 32_000.0,
        },
        "/chatter": {
            "message_type": "std_msgs/msg/String",
            "publishers": 1,
            "subscribers": 1,
            "hz": 1.0,
            "bandwidth_bps": 128.0,
        },
    },
    "stream_overrides": {},
    "diagnostic_degradations": [],
}


def get_sim_state(key: str, default=None):
    return _sim_state.get(key, default)


def set_sim_state(key: str, value):
    _sim_state[key] = value


def active_camera_bridges(max_age_seconds: float = 5.0) -> dict:
    """Return bridged camera entries that are still considered live."""
    bridges = _sim_state.get("camera_bridges", {})
    now = time.time()
    return {
        camera_id: bridge
        for camera_id, bridge in bridges.items()
        if now - bridge.get("last_frame_time", 0) <= max_age_seconds
    }


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def sim_ros_graph() -> dict:
    return {
        "nodes": [
            {"name": "/talker", "kind": "node", "namespace": "/"},
            {"name": "/listener", "kind": "node", "namespace": "/"},
            {"name": "/camera_driver", "kind": "node", "namespace": "/"},
            {"name": "/scan_publisher", "kind": "node", "namespace": "/"},
        ],
        "edges": [
            {
                "from": "/talker",
                "to": "/listener",
                "topic": "/chatter",
                "message_type": "std_msgs/msg/String",
            },
            {
                "from": "/camera_driver",
                "to": "/vision_stack",
                "topic": "/camera/image_raw",
                "message_type": "sensor_msgs/msg/Image",
            },
            {
                "from": "/scan_publisher",
                "to": "/nav2",
                "topic": "/scan",
                "message_type": "sensor_msgs/msg/LaserScan",
            },
        ],
        "captured_at": utc_now_iso(),
    }


def sim_stream_catalog() -> list[dict]:
    streams = [
        {
            "id": "camera-front",
            "name": "Front CSI Camera",
            "kind": "image",
            "origin": "device_camera",
            "device_path": "/dev/video0",
            "message_type": "sensor_msgs/msg/Image",
            "width": 1280,
            "height": 720,
            "nominal_fps": 30.0,
        },
        {
            "id": "camera-image-raw",
            "name": "ROS Image /camera/image_raw",
            "kind": "image",
            "origin": "ros_image_topic",
            "topic": "/camera/image_raw",
            "message_type": "sensor_msgs/msg/Image",
            "width": 1280,
            "height": 720,
            "nominal_fps": 15.0,
        },
        {
            "id": "scan-main",
            "name": "LaserScan /scan",
            "kind": "scan",
            "origin": "ros_laserscan_topic",
            "topic": "/scan",
            "message_type": "sensor_msgs/msg/LaserScan",
            "nominal_fps": 10.0,
        },
    ]

    for camera_id, bridge in active_camera_bridges(max_age_seconds=30).items():
        streams.append({
            "id": camera_id,
            "name": bridge.get("name", "Bridged Camera"),
            "kind": "image",
            "origin": "bridged_camera",
            "device_path": f"bridge:{camera_id}",
            "message_type": "image/jpeg",
            "width": bridge.get("width"),
            "height": bridge.get("height"),
            "nominal_fps": bridge.get("fps"),
        })
    return streams


def sim_stream_health(source_id: str) -> dict:
    overrides = _sim_state.get("stream_overrides", {})
    if source_id in overrides:
        return overrides[source_id]

    if source_id == "scan-main":
        return {
            "source_id": source_id,
            "status": "ready",
            "fps": 10.0,
            "last_frame_at": utc_now_iso(),
            "dropped_frames": 0,
            "stale": False,
            "transport_healthy": True,
            "timestamps_sane": True,
            "expected_rate": True,
        }

    if source_id.startswith("zed-") or source_id in active_camera_bridges(max_age_seconds=30):
        bridge = active_camera_bridges(max_age_seconds=30).get(source_id, {})
        return {
            "source_id": source_id,
            "status": "ready",
            "fps": bridge.get("fps", 15.0),
            "width": bridge.get("width"),
            "height": bridge.get("height"),
            "last_frame_at": bridge.get("captured_at", utc_now_iso()),
            "dropped_frames": 0,
            "stale": False,
            "transport_healthy": True,
            "timestamps_sane": True,
            "expected_rate": True,
        }

    return {
        "source_id": source_id,
        "status": "ready",
        "fps": 15.0 if "camera" in source_id else 10.0,
        "width": 1280 if "camera" in source_id else None,
        "height": 720 if "camera" in source_id else None,
        "last_frame_at": utc_now_iso(),
        "dropped_frames": 0,
        "stale": False,
        "transport_healthy": True,
        "timestamps_sane": True,
        "expected_rate": True,
    }


def sim_laserscan_frame(source_id: str) -> dict:
    ranges = [1.2, 1.4, 1.1, 2.0, 2.4, 3.0, 2.1, 1.9, 1.5, 1.3, 1.0, 0.9]
    return {
        "source_id": source_id,
        "angle_min": -1.57,
        "angle_max": 1.57,
        "angle_increment": 3.14 / len(ranges),
        "range_min": 0.2,
        "range_max": 12.0,
        "ranges": ranges,
        "intensities": [80.0] * len(ranges),
        "captured_at": utc_now_iso(),
    }
