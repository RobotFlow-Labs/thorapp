"""OCI registry trust and readiness management."""

import base64
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit

from fastapi import APIRouter
from fastapi.responses import JSONResponse

from sim import get_sim_state, is_sim, set_sim_state

router = APIRouter(prefix="/v1/registry", tags=["registry"])
DOCKER_CERTS_DIR = Path("/etc/docker/certs.d")


@router.get("/status")
async def registry_status(registry: str, scheme: str = "https"):
    """Report Docker registry trust/auth status on the device."""
    try:
        registry = _validated_registry_address(registry)
    except ValueError as error:
        return JSONResponse(status_code=400, content={"error": str(error)})
    state = _load_registry_state(registry, scheme)
    return state


@router.post("/apply")
async def registry_apply(payload: dict):
    """Apply registry CA trust and optional Docker auth on the device."""
    registry = payload.get("registry", "").strip()
    scheme = payload.get("scheme", "https").strip().lower() or "https"
    ca_certificate_pem = payload.get("ca_certificate_pem", "")
    ca_certificate_base64 = payload.get("ca_certificate_base64", "")
    username = payload.get("username", "")
    password = payload.get("password", "")

    if not registry:
        return JSONResponse(status_code=400, content={"error": "registry required"})
    try:
        registry = _validated_registry_address(registry)
    except ValueError as error:
        return JSONResponse(status_code=400, content={"error": str(error)})

    if is_sim():
        configs = get_sim_state("registry_configs", {})
        config = configs.get(registry, {})
        config.update(
            {
                "scheme": scheme,
                "trusted": scheme == "http" or bool(ca_certificate_pem or ca_certificate_base64),
                "authenticated": bool(username and password),
                "certificate_path": f"/simulated/docker/certs.d/{registry}/ca.crt" if (ca_certificate_pem or ca_certificate_base64) else None,
                "last_applied_at": datetime.now(timezone.utc).isoformat(),
            }
        )
        configs[registry] = config
        set_sim_state("registry_configs", configs)
        return {
            "registry": registry,
            "trusted": config["trusted"],
            "authenticated": config["authenticated"],
            "ready": config["trusted"] and (config["authenticated"] or not username),
            "needs_restart": False,
            "certificate_path": config["certificate_path"],
            "stdout": "Simulated registry configuration applied",
            "stderr": "",
            "message": "Registry trust/auth applied in simulator",
        }

    certificate_path = None
    trusted = scheme == "http"
    authenticated = False
    stdout_lines = []
    stderr_lines = []

    if scheme == "https" and (ca_certificate_pem or ca_certificate_base64):
        certificate_path = str(_docker_certificate_path(registry))
        try:
            _write_certificate(registry, ca_certificate_pem, ca_certificate_base64)
            trusted = True
            stdout_lines.append(f"Wrote CA certificate to {certificate_path}")
        except PermissionError as error:
            stderr_lines.append(str(error))
        except OSError as error:
            stderr_lines.append(f"Failed to write certificate: {error}")

    if username and password:
        try:
            login = subprocess.run(
                ["docker", "login", registry, "--username", username, "--password-stdin"],
                input=password,
                capture_output=True,
                text=True,
                timeout=60,
            )
            stdout_lines.append(login.stdout.strip())
            stderr_lines.append(login.stderr.strip())
            authenticated = login.returncode == 0
        except subprocess.TimeoutExpired:
            stderr_lines.append("docker login timed out")
        except FileNotFoundError:
            stderr_lines.append("Docker not installed")

    if not certificate_path:
        existing = _docker_certificate_path(registry)
        if existing.exists():
            certificate_path = str(existing)
            trusted = True

    ready = trusted and (authenticated or not username)
    return {
        "registry": registry,
        "trusted": trusted,
        "authenticated": authenticated,
        "ready": ready,
        "needs_restart": False,
        "certificate_path": certificate_path,
        "stdout": "\n".join(filter(None, stdout_lines)),
        "stderr": "\n".join(filter(None, stderr_lines)),
        "message": "Registry configuration applied" if ready else "Registry configuration applied with follow-up required",
    }


@router.post("/validate")
async def registry_validate(payload: dict):
    """Validate registry readiness and optionally run a Docker pull preflight."""
    registry = payload.get("registry", "").strip()
    scheme = payload.get("scheme", "https").strip().lower() or "https"
    image = payload.get("image", "").strip()

    if not registry:
        return JSONResponse(status_code=400, content={"error": "registry required"})
    try:
        registry = _validated_registry_address(registry)
    except ValueError as error:
        return JSONResponse(status_code=400, content={"error": str(error)})

    if is_sim():
        configs = get_sim_state("registry_configs", {})
        config = configs.get(registry, {})
        trusted = config.get("trusted", scheme == "http")
        authenticated = config.get("authenticated", False)
        ready = trusted and (authenticated or not image)
        stages = [
            {"name": "Device Registry State", "status": "pass" if trusted else "warning", "message": "Registry trust applied in simulator." if trusted else "Registry trust not applied on simulator."},
            {"name": "Device Auth State", "status": "pass" if authenticated or not image else "warning", "message": "Registry auth available in simulator." if authenticated else "No simulator auth recorded."},
        ]
        if image:
            stages.append(
                {
                    "name": "Device Pull Preflight",
                    "status": "pass" if ready else "fail",
                    "message": f"Simulated pull ready for {image}." if ready else f"Simulated pull would fail for {image}.",
                }
            )
        return {
            "registry": registry,
            "status": _overall_status(stages),
            "trusted": trusted,
            "authenticated": authenticated,
            "ready": ready,
            "stages": stages,
        }

    state = _load_registry_state(registry, scheme)
    stages = [
        {
            "name": "Device Registry State",
            "status": "pass" if state["trusted"] else "warning",
            "message": state["message"],
        },
        {
            "name": "Device Auth State",
            "status": "pass" if state["authenticated"] else "warning",
            "message": "Docker auth is configured for this registry." if state["authenticated"] else "No Docker auth entry found for this registry.",
        },
    ]

    ready = state["trusted"] or scheme == "http"

    if image:
        try:
            pull = subprocess.run(
                ["docker", "pull", image],
                capture_output=True,
                text=True,
                timeout=180,
            )
            if pull.returncode == 0:
                stages.append(
                    {
                        "name": "Device Pull Preflight",
                        "status": "pass",
                        "message": f"Docker pull succeeded for {image}.",
                    }
                )
                ready = True
            else:
                stages.append(
                    {
                        "name": "Device Pull Preflight",
                        "status": "fail",
                        "message": (pull.stderr or pull.stdout or f"Docker pull failed for {image}.").strip()[-300:],
                    }
                )
                ready = False
        except subprocess.TimeoutExpired:
            stages.append(
                {
                    "name": "Device Pull Preflight",
                    "status": "fail",
                    "message": f"Docker pull timed out for {image}.",
                }
            )
            ready = False
        except FileNotFoundError:
            stages.append(
                {
                    "name": "Device Pull Preflight",
                    "status": "fail",
                    "message": "Docker not installed on device.",
                }
            )
            ready = False

    return {
        "registry": registry,
        "status": _overall_status(stages),
        "trusted": state["trusted"],
        "authenticated": state["authenticated"],
        "ready": ready,
        "stages": stages,
    }


def _docker_certificate_path(registry: str) -> Path:
    target = (DOCKER_CERTS_DIR / registry / "ca.crt").resolve()
    base_dir = DOCKER_CERTS_DIR.resolve()
    try:
        target.relative_to(base_dir)
    except ValueError as error:
        raise ValueError("Invalid registry address. Use host[:port].") from error
    return target


def _validated_registry_address(registry: str) -> str:
    registry = registry.strip()
    if not registry:
        raise ValueError("registry required")
    if len(registry) > 255:
        raise ValueError("Invalid registry address. Use host[:port].")
    if any(char in registry for char in ["/", "\\", "\0", "\n", "\r", "\t", " "]):
        raise ValueError("Invalid registry address. Use host[:port].")

    try:
        parsed = urlsplit(f"//{registry}")
        port = parsed.port
    except ValueError as error:
        raise ValueError("Invalid registry address. Use host[:port].") from error

    if parsed.path not in ("", "/") or parsed.query or parsed.fragment or parsed.username or parsed.password:
        raise ValueError("Invalid registry address. Use host[:port].")
    if not parsed.hostname or ".." in parsed.hostname:
        raise ValueError("Invalid registry address. Use host[:port].")
    if port is not None and not (1 <= port <= 65535):
        raise ValueError("Invalid registry address. Use host[:port].")

    return registry


def _write_certificate(registry: str, certificate_pem: str, certificate_base64: str) -> None:
    cert_path = _docker_certificate_path(registry)
    cert_path.parent.mkdir(parents=True, exist_ok=True)
    if certificate_base64:
        cert_path.write_bytes(base64.b64decode(certificate_base64))
    else:
        cert_path.write_text(certificate_pem)


def _load_registry_state(registry: str, scheme: str) -> dict:
    cert_path = _docker_certificate_path(registry)
    trusted = scheme == "http" or cert_path.exists()

    docker_config_path = Path.home() / ".docker" / "config.json"
    authenticated = False
    docker_config_available = False
    try:
        docker_config_available = docker_config_path.exists()
    except PermissionError:
        docker_config_available = False

    if docker_config_available:
        try:
            config = json.loads(docker_config_path.read_text())
            auths = config.get("auths", {})
            authenticated = registry in auths
        except (OSError, PermissionError, json.JSONDecodeError):
            authenticated = False

    if trusted:
        message = "Registry CA is installed for Docker on this device." if cert_path.exists() else "HTTP registry does not require CA trust."
    else:
        message = "Registry CA is not installed for Docker on this device."

    return {
        "registry": registry,
        "trusted": trusted,
        "authenticated": authenticated,
        "ready": trusted,
        "needs_restart": False,
        "certificate_path": str(cert_path) if cert_path.exists() else None,
        "docker_config_path": str(docker_config_path) if docker_config_available else None,
        "message": message,
    }


def _overall_status(stages: list[dict]) -> str:
    if any(stage["status"] == "fail" for stage in stages):
        return "fail"
    if any(stage["status"] == "warning" for stage in stages):
        return "warning"
    return "pass"
