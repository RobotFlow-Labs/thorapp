# thorctl Skill — Jetson Control Surface

## Rule: Use thorctl to inspect and control Jetson devices

When working on this project, **always use thorctl** to verify changes against the real Docker simulator. Do not guess device state — query it.

## Before any device-related work

```bash
# Ensure Docker sims are running
make docker-up

# Verify both sims are healthy
thorctl health 8470    # Thor sim
thorctl health 8471    # Orin sim
```

## After making agent changes

```bash
# Rebuild Docker sims
docker compose down && docker compose build --no-cache && docker compose up -d
sleep 5

# Verify endpoints work
thorctl health 8470
thorctl caps 8470
```

## After making Swift changes

```bash
swift build              # Must be 0 errors, 0 warnings
swift test               # Must be 71+ tests passing
make run                 # Package + launch app
```

## thorctl Command Reference

### Device Status
```bash
thorctl health [port]              # Agent health check
thorctl connect <host> [port]      # Connect and show full device info
thorctl caps [port]                # Hardware, OS, JetPack, Docker, ROS2, GPU
thorctl metrics [port]             # CPU, memory, disk, load, temps
thorctl devices                    # List registered devices from DB
```

### System Management
```bash
thorctl sysinfo [port]             # Model, hostname, OS, kernel, JetPack, uptime
thorctl disks [port]               # Filesystem usage table
thorctl network [port]             # Interface table: name, state, IP, MAC
thorctl exec <port> <command>      # Execute any command on device
```

### Power & Performance
```bash
thorctl power [port]               # Power mode (MAXN/30W/15W), clocks, fan speed
```

### Hardware Detection
```bash
thorctl cameras [port]             # List cameras: CSI, USB, ZED with device paths
thorctl usb [port]                 # USB device enumeration
thorctl gpu [port]                 # GPU name, CUDA, TensorRT, memory, models
```

### Docker Management
```bash
thorctl docker [port]              # List containers: name, image, state, status
```

### ROS2
```bash
thorctl ros2-nodes [port]          # List active ROS2 nodes
thorctl ros2-topics [port]         # List topics with message types
thorctl ros2-echo [port] <topic>   # Echo a message from a topic
```

### ANIMA AI Modules
```bash
thorctl modules [port]             # List ANIMA modules with capabilities
thorctl anima-status [port]        # Show running pipeline status
thorctl anima-deploy <port> <yaml> # Deploy pipeline from compose YAML
thorctl anima-stop <port> [name]   # Stop a running pipeline
```

### Monitoring & Debug
```bash
thorctl watch [port] [interval]    # Live metrics dashboard (Ctrl+C to stop)
thorctl screenshot [filename]      # Capture macOS screenshot
thorctl version                    # Show thorctl version
```

## Agent Endpoints (50 total)

### Core (main.py)
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /v1/health | Agent health + version |
| GET | /v1/capabilities | Full device capabilities |
| GET | /v1/metrics | CPU, memory, disk, temps, network |
| POST | /v1/exec | Execute guarded command |
| GET | /v1/services | List systemd services |

### Power (routers/power.py)
| Method | Endpoint | Linux Command |
|--------|----------|---------------|
| GET | /v1/power/mode | `nvpmodel -q` |
| POST | /v1/power/mode | `sudo nvpmodel -m N` |
| GET | /v1/power/clocks | `jetson_clocks --show` |
| POST | /v1/power/clocks | `sudo jetson_clocks` |
| GET | /v1/power/fan | read `/sys/devices/pwm-fan/` |
| POST | /v1/power/fan | write PWM value |

### System (routers/system.py)
| Method | Endpoint | Linux Command |
|--------|----------|---------------|
| GET | /v1/system/info | `uname`, `/etc/nv_tegra_release` |
| GET | /v1/system/packages | `dpkg -l` |
| POST | /v1/system/packages | `sudo apt update/upgrade` |
| GET | /v1/system/users | `getent passwd` |
| POST | /v1/system/reboot | `sudo reboot` (requires confirm) |

### Storage (routers/storage.py)
| Method | Endpoint | Linux Command |
|--------|----------|---------------|
| GET | /v1/storage/disks | `lsblk -J`, `df -h`, `smartctl` |
| GET | /v1/storage/swap | `free -h`, `swapon --show` |
| POST | /v1/storage/swap | `swapon`/`swapoff` |

### Network (routers/network.py)
| Method | Endpoint | Linux Command |
|--------|----------|---------------|
| GET | /v1/network/interfaces | `ip -j addr show` |
| GET | /v1/network/wifi | `nmcli device wifi list` |
| POST | /v1/network/wifi | `nmcli device wifi connect` |

### Hardware (routers/hardware.py)
| Method | Endpoint | Linux Command |
|--------|----------|---------------|
| GET | /v1/hardware/cameras | `v4l2-ctl --list-devices`, `lsusb` |
| GET | /v1/hardware/gpio | read `/sys/class/gpio/` |
| GET | /v1/hardware/i2c | `i2cdetect -y BUS` |
| GET | /v1/hardware/usb | `lsusb` |
| GET | /v1/hardware/serial | `ls /dev/tty{USB,ACM,THS}*` |

### ROS2 (routers/ros2.py)
| Method | Endpoint | Linux Command |
|--------|----------|---------------|
| GET | /v1/ros2/nodes | `ros2 node list` |
| GET | /v1/ros2/topics | `ros2 topic list -t` |
| GET | /v1/ros2/services | `ros2 service list -t` |
| POST | /v1/ros2/launch | `ros2 launch PKG FILE` |
| POST | /v1/ros2/launch/stop | kill PID |
| GET | /v1/ros2/launches | list running launches |
| GET | /v1/ros2/lifecycle | `ros2 lifecycle nodes` |
| POST | /v1/ros2/lifecycle | `ros2 lifecycle set NODE TRANS` |
| POST | /v1/ros2/topic/echo | `ros2 topic echo --once` |
| POST | /v1/ros2/topic/pub | `ros2 topic pub --once` |
| POST | /v1/ros2/bag/record | `ros2 bag record` |
| POST | /v1/ros2/bag/stop | kill recording |
| GET | /v1/ros2/bags | list recorded bags |
| POST | /v1/ros2/bag/play | `ros2 bag play` |

### GPU (routers/gpu.py)
| Method | Endpoint | Linux Command |
|--------|----------|---------------|
| GET | /v1/gpu/info | `nvcc --version`, `nvidia-smi` |
| GET | /v1/gpu/tensorrt/engines | find `.trt` files |
| POST | /v1/gpu/tensorrt/convert | `trtexec --onnx=X` |
| GET | /v1/models/list | scan model directory |
| POST | /v1/models/upload | multipart file upload |

### Docker (routers/docker.py)
| Method | Endpoint | Linux Command |
|--------|----------|---------------|
| GET | /v1/docker/containers | `docker ps -a` |
| POST | /v1/docker/action | `docker start/stop/restart/remove` |
| GET | /v1/docker/logs/{id} | `docker logs --tail N` |
| GET | /v1/docker/images | `docker images` |
| POST | /v1/docker/pull | `docker pull IMAGE` |

### Logs (routers/logs.py)
| Method | Endpoint | Linux Command |
|--------|----------|---------------|
| GET | /v1/logs/system | `journalctl` |
| GET | /v1/logs/agent | agent self-logs |

### ANIMA (routers/anima.py)
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /v1/anima/modules | scan anima_module.yaml manifests |
| POST | /v1/anima/deploy | docker compose up from YAML |
| GET | /v1/anima/status | pipeline container states |
| POST | /v1/anima/stop | docker compose down |

## Docker Simulator Quick Reference

```bash
# Start sims
docker compose up -d

# Thor sim: SSH port 2222, Agent port 8470
# Orin sim: SSH port 2223, Agent port 8471
# Default creds: jetson / jetson

# ROS2 demo: /talker + /listener nodes on /chatter topic
# Docker: sees host Docker containers via socket mount

# Rebuild after agent changes
docker compose down && docker compose build --no-cache && docker compose up -d
```
