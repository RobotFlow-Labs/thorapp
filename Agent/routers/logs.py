"""Log streaming: system, agent, services."""

import subprocess
from fastapi import APIRouter

AGENT_VERSION = "0.1.0"

router = APIRouter(prefix="/v1/logs", tags=["logs"])


@router.get("/system")
async def system_logs(lines: int = 100, unit: str = ""):
    """Get system journal logs."""
    cmd = ["journalctl", "--no-pager", "-n", str(lines), "--output", "short-iso"]
    if unit:
        cmd += ["-u", unit]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        log_lines = result.stdout.strip().split("\n") if result.stdout.strip() else []
        return {"source": unit or "system", "lines": log_lines, "count": len(log_lines)}
    except FileNotFoundError:
        return {"source": unit or "system", "lines": [], "error": "journalctl not available"}


@router.get("/agent")
async def agent_logs(lines: int = 50):
    """Get THOR agent logs."""
    return {
        "source": "thor-agent",
        "lines": [f"[THOR Agent] Running on 127.0.0.1:8470 — agent v{AGENT_VERSION}"],
        "count": 1,
    }
