"""Background process tracking for long-running operations (ROS2 launch, bag record, trtexec)."""

import os
import signal
import subprocess
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional


@dataclass
class ManagedProcess:
    pid: int
    command: str
    category: str  # "ros2_launch", "ros2_bag", "trt_convert"
    started_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    process: Optional[subprocess.Popen] = field(default=None, repr=False)


class ProcessManager:
    def __init__(self):
        self._processes: dict[int, ManagedProcess] = {}

    def start(self, command: list[str], category: str, cwd: str = "/") -> ManagedProcess:
        """Start a background process and track it."""
        proc = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=cwd,
            preexec_fn=os.setsid,  # new process group for clean kill
        )
        managed = ManagedProcess(
            pid=proc.pid,
            command=" ".join(command),
            category=category,
            process=proc,
        )
        self._processes[proc.pid] = managed
        return managed

    def stop(self, pid: int) -> bool:
        """Stop a tracked process."""
        managed = self._processes.get(pid)
        if not managed:
            return False

        try:
            if managed.process and managed.process.poll() is None:
                os.killpg(os.getpgid(pid), signal.SIGTERM)
                managed.process.wait(timeout=5)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                os.killpg(os.getpgid(pid), signal.SIGKILL)
            except ProcessLookupError:
                pass

        del self._processes[pid]
        return True

    def list(self, category: str = None) -> list[dict]:
        """List tracked processes, optionally filtered by category."""
        self._cleanup()
        result = []
        for pid, managed in self._processes.items():
            if category and managed.category != category:
                continue
            result.append({
                "pid": managed.pid,
                "command": managed.command,
                "category": managed.category,
                "started_at": managed.started_at,
                "running": managed.process.poll() is None if managed.process else False,
            })
        return result

    def is_running(self, pid: int) -> bool:
        """Check if a process is still running."""
        managed = self._processes.get(pid)
        if not managed or not managed.process:
            return False
        return managed.process.poll() is None

    def _cleanup(self):
        """Remove finished processes."""
        dead = [pid for pid, m in self._processes.items()
                if m.process and m.process.poll() is not None]
        for pid in dead:
            del self._processes[pid]


# Global instance
process_manager = ProcessManager()
