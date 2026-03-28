#!/bin/bash
set -e

# Generate SSH host keys if missing
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -A
fi

# Start SSH daemon
/usr/sbin/sshd

# Source ROS2
source /opt/ros/humble/setup.bash 2>/dev/null || true

# Create ROS2 log directory for jetson user
mkdir -p /tmp/ros_logs
chown jetson:jetson /tmp/ros_logs

# Fix Docker socket permissions (Docker-in-Docker)
if [ -e /var/run/docker.sock ]; then
    chmod 666 /var/run/docker.sock
    echo "[entrypoint] Docker socket permissions fixed"
fi

# Start ROS2 demo talker + listener in background (live topics for testing)
su -c "source /opt/ros/humble/setup.bash && ROS_LOG_DIR=/tmp/ros_logs ros2 run demo_nodes_py talker &" jetson 2>/dev/null &
su -c "source /opt/ros/humble/setup.bash && ROS_LOG_DIR=/tmp/ros_logs ros2 run demo_nodes_py listener &" jetson 2>/dev/null &

# Export env vars for the agent process
export THOR_AGENT_HOST=0.0.0.0

# Start THOR agent as jetson user, preserving environment
echo "[entrypoint] Starting THOR Agent on port 8470..."
echo "[entrypoint] Model: ${THOR_SIM_MODEL:-unknown}, Serial: ${THOR_SIM_SERIAL:-unknown}"
echo "[entrypoint] ROS2 talker+listener started on /chatter topic"
echo "[entrypoint] Docker: $(docker --version 2>/dev/null || echo 'not available')"

exec su -m jetson -c "source /opt/ros/humble/setup.bash 2>/dev/null; ROS_LOG_DIR=/tmp/ros_logs THOR_AGENT_HOST=${THOR_AGENT_HOST} THOR_SIM_MODEL='${THOR_SIM_MODEL}' THOR_SIM_SERIAL='${THOR_SIM_SERIAL}' THOR_SIM_JETPACK='${THOR_SIM_JETPACK}' python3 /opt/thor-agent/main.py"
