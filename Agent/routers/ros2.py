"""ROS2 lifecycle: nodes, topics, services, launch, lifecycle, bags."""

import os
import re
import shlex
import subprocess
from fastapi import APIRouter
from fastapi.responses import JSONResponse
from process_manager import process_manager

router = APIRouter(prefix="/v1/ros2", tags=["ros2"])

# ROS2 environment setup
ROS2_SETUP = "/opt/ros/humble/setup.bash"
ROS2_ENV = {**os.environ, "ROS_LOG_DIR": "/tmp/ros_logs", "HOME": os.environ.get("HOME", "/home/jetson")}


def _ros2_cmd(args: list[str], timeout: int = 10) -> subprocess.CompletedProcess:
    """Run a ROS2 command with proper environment sourcing.

    All user-provided arguments MUST be passed through shlex.quote() before
    being added to args to prevent shell injection.
    """
    # Quote each argument for shell safety
    safe_args = [shlex.quote(a) for a in args]
    cmd = f"source {ROS2_SETUP} 2>/dev/null && {' '.join(safe_args)}"
    return subprocess.run(
        ["bash", "-c", cmd],
        capture_output=True, text=True, timeout=timeout,
        env=ROS2_ENV,
    )


def _validate_ros2_name(name: str) -> bool:
    """Validate a ROS2 name (node, topic, package) is safe."""
    return bool(re.match(r'^[a-zA-Z0-9/_\-\.]+$', name)) and len(name) < 256


@router.get("/nodes")
async def ros2_nodes():
    """List ROS2 nodes."""
    try:
        result = _ros2_cmd(["ros2", "node", "list"])
        nodes = [n.strip() for n in result.stdout.strip().split("\n") if n.strip()]
        return {"nodes": nodes, "count": len(nodes)}
    except FileNotFoundError:
        return {"nodes": [], "count": 0, "error": "ROS2 not installed"}


@router.get("/topics")
async def ros2_topics():
    """List ROS2 topics with types."""
    try:
        result = _ros2_cmd(["ros2", "topic", "list", "-t"])
        topics = []
        for line in result.stdout.strip().split("\n"):
            if line.strip():
                parts = line.strip().split(" [")
                name = parts[0].strip()
                msg_type = parts[1].rstrip("]") if len(parts) > 1 else "unknown"
                topics.append({"name": name, "type": msg_type})
        return {"topics": topics, "count": len(topics)}
    except FileNotFoundError:
        return {"topics": [], "count": 0, "error": "ROS2 not installed"}


@router.get("/services")
async def ros2_services():
    """List ROS2 services with types."""
    try:
        result = _ros2_cmd(["ros2", "service", "list", "-t"])
        services = []
        for line in result.stdout.strip().split("\n"):
            if line.strip():
                parts = line.strip().split(" [")
                name = parts[0].strip()
                srv_type = parts[1].rstrip("]") if len(parts) > 1 else "unknown"
                services.append({"name": name, "type": srv_type})
        return {"services": services, "count": len(services)}
    except FileNotFoundError:
        return {"services": [], "count": 0, "error": "ROS2 not installed"}


@router.post("/launch")
async def ros2_launch(payload: dict):
    """Launch a ROS2 launch file (background process)."""
    package = payload.get("package", "")
    launch_file = payload.get("launch_file", "")

    if not package or not launch_file:
        return JSONResponse(status_code=400, content={"error": "package and launch_file required"})
    if not _validate_ros2_name(package) or not _validate_ros2_name(launch_file):
        return JSONResponse(status_code=400, content={"error": "Invalid package or launch file name"})

    try:
        managed = process_manager.start(
            ["ros2", "launch", package, launch_file],
            category="ros2_launch"
        )
        return {"pid": managed.pid, "status": "launched", "package": package, "launch_file": launch_file}
    except Exception as e:
        return JSONResponse(status_code=500, content={"error": str(e)})


@router.post("/launch/stop")
async def ros2_launch_stop(payload: dict):
    """Stop a running launch."""
    pid = payload.get("pid", 0)
    if process_manager.stop(pid):
        return {"pid": pid, "status": "stopped"}
    return JSONResponse(status_code=404, content={"error": f"Process {pid} not found"})


@router.get("/launches")
async def ros2_launches():
    """List running launches."""
    return {"launches": process_manager.list(category="ros2_launch")}


@router.get("/lifecycle")
async def ros2_lifecycle():
    """List lifecycle-managed nodes."""
    try:
        result = _ros2_cmd(["ros2", "lifecycle", "nodes"])
        nodes = []
        for name in result.stdout.strip().split("\n"):
            if name.strip():
                # Get state for each
                state_result = _ros2_cmd(["ros2", "lifecycle", "get", name.strip()])
                state = state_result.stdout.strip() if state_result.returncode == 0 else "unknown"
                nodes.append({"name": name.strip(), "state": state})
        return {"nodes": nodes}
    except FileNotFoundError:
        return {"nodes": [], "error": "ROS2 not installed"}


@router.post("/lifecycle")
async def ros2_lifecycle_transition(payload: dict):
    """Transition a lifecycle node."""
    node = payload.get("node", "")
    transition = payload.get("transition", "")

    if not node or not transition:
        return JSONResponse(status_code=400, content={"error": "node and transition required"})
    if not _validate_ros2_name(node):
        return JSONResponse(status_code=400, content={"error": "Invalid node name"})

    valid_transitions = ["configure", "activate", "deactivate", "cleanup", "shutdown"]
    if transition not in valid_transitions:
        return JSONResponse(status_code=400, content={"error": f"Invalid transition. Use: {valid_transitions}"})

    try:
        result = _ros2_cmd(["ros2", "lifecycle", "set", node, transition])
        return {"node": node, "transition": transition, "success": result.returncode == 0, "output": result.stdout}
    except FileNotFoundError:
        return JSONResponse(status_code=500, content={"error": "ROS2 not installed"})


@router.post("/topic/echo")
async def ros2_topic_echo(payload: dict):
    """Echo a single message from a topic."""
    topic = payload.get("topic", "")
    if not topic or not _validate_ros2_name(topic):
        return JSONResponse(status_code=400, content={"error": "Valid topic name required"})
    try:
        result = _ros2_cmd(["ros2", "topic", "echo", "--once", topic])
        return {"topic": topic, "message": result.stdout, "error": result.stderr if result.returncode != 0 else None}
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        return {"topic": topic, "message": None, "error": str(e)}


@router.post("/topic/pub")
async def ros2_topic_pub(payload: dict):
    """Publish a single message to a topic."""
    topic = payload.get("topic", "")
    msg_type = payload.get("type", "")
    data = payload.get("data", "")

    if not topic or not msg_type:
        return JSONResponse(status_code=400, content={"error": "topic and type required"})
    if not _validate_ros2_name(topic) or not _validate_ros2_name(msg_type):
        return JSONResponse(status_code=400, content={"error": "Invalid topic or message type name"})
    try:
        result = _ros2_cmd(["ros2", "topic", "pub", "--once", topic, msg_type, data])
        return {"topic": topic, "type": msg_type, "success": result.returncode == 0}
    except FileNotFoundError:
        return {"success": False, "error": "ROS2 not installed"}


@router.post("/bag/record")
async def ros2_bag_record(payload: dict):
    """Start recording a ROS2 bag."""
    topics = payload.get("topics", [])
    output = payload.get("output", "/tmp/thor_bag")

    cmd = ["ros2", "bag", "record", "-o", output]
    if topics:
        cmd.extend(topics)
    else:
        cmd.append("-a")

    try:
        managed = process_manager.start(cmd, category="ros2_bag")
        return {"pid": managed.pid, "status": "recording", "output": output}
    except Exception as e:
        return JSONResponse(status_code=500, content={"error": str(e)})


@router.post("/bag/stop")
async def ros2_bag_stop(payload: dict):
    """Stop a bag recording."""
    pid = payload.get("pid", 0)
    if process_manager.stop(pid):
        return {"pid": pid, "status": "stopped"}
    return JSONResponse(status_code=404, content={"error": f"Process {pid} not found"})


@router.get("/bags")
async def ros2_bag_list():
    """List recorded bags."""
    bag_dirs = ["/tmp", "/home/jetson/bags", "/opt/ros2_bags"]
    bags = []

    for bag_dir in bag_dirs:
        if not os.path.isdir(bag_dir):
            continue
        for entry in os.listdir(bag_dir):
            metadata = os.path.join(bag_dir, entry, "metadata.yaml")
            if os.path.exists(metadata):
                size = sum(
                    os.path.getsize(os.path.join(bag_dir, entry, f))
                    for f in os.listdir(os.path.join(bag_dir, entry))
                    if os.path.isfile(os.path.join(bag_dir, entry, f))
                )
                bags.append({
                    "name": entry,
                    "path": os.path.join(bag_dir, entry),
                    "size_bytes": size,
                })

    return {"bags": bags, "recordings": process_manager.list(category="ros2_bag")}


@router.post("/bag/play")
async def ros2_bag_play(payload: dict):
    """Play a recorded bag."""
    bag_path = payload.get("bag_path", "")
    rate = payload.get("rate", 1.0)

    if not bag_path:
        return JSONResponse(status_code=400, content={"error": "bag_path required"})

    # Validate bag path — must be in known directories
    allowed_dirs = ["/tmp", "/home/jetson/bags", "/opt/ros2_bags"]
    real_path = os.path.realpath(bag_path)
    if not any(real_path.startswith(d) for d in allowed_dirs):
        return JSONResponse(status_code=403, content={"error": "Bag path must be in /tmp, /home/jetson/bags, or /opt/ros2_bags"})

    cmd = ["ros2", "bag", "play", bag_path]
    if rate != 1.0:
        cmd.extend(["--rate", str(rate)])

    try:
        managed = process_manager.start(cmd, category="ros2_bag_play")
        return {"pid": managed.pid, "status": "playing", "bag_path": bag_path}
    except Exception as e:
        return JSONResponse(status_code=500, content={"error": str(e)})
