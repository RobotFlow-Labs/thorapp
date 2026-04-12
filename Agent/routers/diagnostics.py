"""Device-side diagnostics archive collection."""

import io
import json
import os
import shutil
import zipfile
from datetime import datetime, timezone

import psutil
from fastapi import APIRouter
from fastapi.responses import Response

from process_manager import process_manager
from sim import get_distro, get_sim_state, is_sim, sim_identity, sim_ros_graph, sim_stream_catalog, sim_stream_health

router = APIRouter(prefix="/v1/diagnostics", tags=["diagnostics"])


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _collect_capabilities() -> dict:
    disk = shutil.disk_usage("/")
    identity = sim_identity()
    return {
        "model": identity.get("model", "Unknown"),
        "jetpack": identity.get("jetpack"),
        "os": get_distro(),
        "disk_total_gb": round(disk.total / (1024 ** 3), 1),
        "disk_free_gb": round(disk.free / (1024 ** 3), 1),
    }


def _collect_metrics() -> dict:
    vm = psutil.virtual_memory()
    disk = shutil.disk_usage("/")
    return {
        "timestamp": _utc_now(),
        "cpu_percent": psutil.cpu_percent(interval=0.1),
        "memory_used_mb": vm.used // (1024 * 1024),
        "memory_total_mb": vm.total // (1024 * 1024),
        "disk_used_gb": round(disk.used / (1024 ** 3), 1),
        "disk_total_gb": round(disk.total / (1024 ** 3), 1),
        "load_avg": list(os.getloadavg()),
    }


def _collect_system_metrics() -> dict:
    temps = {}
    try:
        for name, entries in psutil.sensors_temperatures().items():
            for entry in entries:
                temps[f"{name}/{entry.label or 'main'}"] = entry.current
    except (AttributeError, RuntimeError):
        pass
    return {
        "temps": temps,
        "power_mode": get_sim_state_or_none("power_mode"),
        "fan_speed": get_sim_state_or_none("fan_speed"),
    }


def get_sim_state_or_none(key: str):
    try:
        return get_sim_state(key)
    except Exception:
        return None


@router.post("/archive")
async def diagnostics_archive(payload: dict):
    """Collect a zip archive containing structured diagnostics."""
    requested_sections = payload.get("sections") or []
    default_sections = [
        "capabilities",
        "metrics",
        "system",
        "ros2",
        "streams",
        "processes",
    ]
    sections = requested_sections if requested_sections else default_sections

    bundle = io.BytesIO()
    with zipfile.ZipFile(bundle, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        manifest = {
            "collected_at": _utc_now(),
            "sections": sections,
            "simulator": is_sim(),
        }
        archive.writestr("manifest.json", json.dumps(manifest, indent=2, sort_keys=True))

        if "capabilities" in sections:
            archive.writestr("capabilities.json", json.dumps(_collect_capabilities(), indent=2, sort_keys=True))

        if "metrics" in sections:
            archive.writestr("metrics.json", json.dumps(_collect_metrics(), indent=2, sort_keys=True))

        if "system" in sections:
            archive.writestr("system.json", json.dumps(_collect_system_metrics(), indent=2, sort_keys=True))

        if "ros2" in sections:
            archive.writestr(
                "ros2/graph.json",
                json.dumps(sim_ros_graph() if is_sim() else {"nodes": [], "edges": [], "captured_at": _utc_now()}, indent=2, sort_keys=True),
            )
            archive.writestr(
                "ros2/processes.json",
                json.dumps({
                    "launches": process_manager.list(category="ros2_launch"),
                    "bags": process_manager.list(category="ros2_bag"),
                }, indent=2, sort_keys=True),
            )

        if "streams" in sections:
            streams = sim_stream_catalog() if is_sim() else []
            archive.writestr("streams/catalog.json", json.dumps(streams, indent=2, sort_keys=True))
            archive.writestr(
                "streams/health.json",
                json.dumps({stream["id"]: sim_stream_health(stream["id"]) for stream in streams}, indent=2, sort_keys=True),
            )

        if "processes" in sections:
            archive.writestr(
                "processes.json",
                json.dumps({
                    "tracked": process_manager.list(),
                    "uptime_seconds": int(psutil.boot_time()),
                }, indent=2, sort_keys=True),
            )

        archive.writestr(
            "SUMMARY.md",
            "\n".join([
                "# THOR Diagnostics",
                "",
                f"- Collected: {_utc_now()}",
                f"- Simulator: {'yes' if is_sim() else 'no'}",
                f"- Sections: {', '.join(sections)}",
            ]),
        )

    bundle.seek(0)
    return Response(
        content=bundle.getvalue(),
        media_type="application/zip",
        headers={
            "Content-Disposition": 'attachment; filename="thor-diagnostics.zip"',
            "Cache-Control": "no-store, max-age=0",
        },
    )
