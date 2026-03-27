#!/bin/bash
set -e

# Generate SSH host keys if missing
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -A
fi

# Start SSH daemon
/usr/sbin/sshd

# Start THOR agent as jetson user
echo "[entrypoint] Starting THOR Agent on port 8470..."
exec su - jetson -c "python3 /opt/thor-agent/main.py"
