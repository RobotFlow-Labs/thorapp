#!/bin/bash
set -e

# Generate SSH host keys if missing
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -A
fi

# Start SSH daemon
/usr/sbin/sshd

# Export env vars for the agent process
export THOR_AGENT_HOST=0.0.0.0

# Start THOR agent as jetson user, preserving environment
echo "[entrypoint] Starting THOR Agent on port 8470..."
echo "[entrypoint] Model: ${THOR_SIM_MODEL:-unknown}, Serial: ${THOR_SIM_SERIAL:-unknown}"
exec su -m jetson -c "THOR_AGENT_HOST=${THOR_AGENT_HOST} THOR_SIM_MODEL='${THOR_SIM_MODEL}' THOR_SIM_SERIAL='${THOR_SIM_SERIAL}' THOR_SIM_JETPACK='${THOR_SIM_JETPACK}' python3 /opt/thor-agent/main.py"
