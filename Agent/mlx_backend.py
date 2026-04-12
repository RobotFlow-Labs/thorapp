"""Helpers for integrating docker_mlx_cpp as a host-side compute backend."""

import http.client
import json
import os
import time
import urllib.error
import urllib.request


MLX_DAEMON_URL = os.environ.get("THOR_MLX_DAEMON_URL", "http://host.docker.internal:12435").rstrip("/")
MLX_GATEWAY_URL = os.environ.get("THOR_MLX_GATEWAY_URL", "http://host.docker.internal:8080").rstrip("/")
MLX_REQUEST_TIMEOUT = float(os.environ.get("THOR_MLX_TIMEOUT_SECONDS", "1.5"))
MLX_CACHE_TTL_SECONDS = float(os.environ.get("THOR_MLX_CACHE_TTL_SECONDS", "2.0"))

_mlx_cache = {
    "status": None,
    "expires_at": 0.0,
}


def _candidate_base_urls() -> list[str]:
    seen = set()
    urls = []
    for url in (MLX_DAEMON_URL, MLX_GATEWAY_URL):
        if url and url not in seen:
            seen.add(url)
            urls.append(url)
    return urls


def _fetch_json(url: str):
    try:
        with urllib.request.urlopen(url, timeout=MLX_REQUEST_TIMEOUT) as response:
            if response.status != 200:
                return None
            payload = response.read().decode("utf-8")
            return json.loads(payload)
    except (
        TimeoutError,
        ValueError,
        OSError,
        ConnectionError,
        json.JSONDecodeError,
        http.client.HTTPException,
        urllib.error.URLError,
        urllib.error.HTTPError,
    ):
        return None


def _normalize_health_payload(health_payload: dict) -> dict:
    if "mlx_daemon" in health_payload and isinstance(health_payload["mlx_daemon"], dict):
        return health_payload["mlx_daemon"]
    return health_payload


def mlx_backend_status(force_refresh: bool = False):
    now = time.time()
    if not force_refresh and _mlx_cache["status"] is not None and now < _mlx_cache["expires_at"]:
        return _mlx_cache["status"]

    normalized_status = None

    for base_url in _candidate_base_urls():
        health_payload = _fetch_json(f"{base_url}/health")
        if not health_payload:
            continue

        daemon_health = _normalize_health_payload(health_payload)
        if daemon_health.get("status") not in ("healthy", "degraded"):
            continue

        gpu_payload = _fetch_json(f"{base_url}/gpu") or {}
        models_payload = _fetch_json(f"{base_url}/v1/models") or {}
        engines_payload = _fetch_json(f"{base_url}/engines") or {}

        daemon_gpu = daemon_health.get("gpu", {}) if isinstance(daemon_health.get("gpu"), dict) else {}
        active_memory_mb = int(round((gpu_payload.get("active_memory_gb") or 0) * 1024))
        total_memory_mb = int(round((daemon_gpu.get("memory_total_gb") or 0) * 1024))
        used_memory_mb = daemon_gpu.get("memory_used_gb")
        if used_memory_mb is None:
            used_memory_mb = active_memory_mb / 1024 if active_memory_mb else 0
        used_memory_mb = int(round(used_memory_mb * 1024))

        loaded_models = daemon_health.get("loaded_models", [])
        if isinstance(loaded_models, list):
            loaded_model_count = len(loaded_models)
        else:
            loaded_model_count = int(loaded_models or 0)

        models = models_payload.get("data", []) if isinstance(models_payload.get("data"), list) else []

        normalized_status = {
            "available": True,
            "base_url": base_url,
            "runtime_label": "docker_mlx_cpp",
            "daemon_version": daemon_health.get("version"),
            "metal_available": bool(daemon_gpu.get("metal_available")),
            "chip": daemon_gpu.get("chip"),
            "platform": daemon_gpu.get("platform"),
            "mlx_backend": daemon_gpu.get("mlx_backend") or gpu_payload.get("default_device"),
            "memory_total_mb": total_memory_mb,
            "memory_used_mb": used_memory_mb,
            "memory_active_mb": active_memory_mb,
            "memory_peak_mb": int(round((gpu_payload.get("peak_memory_gb") or 0) * 1024)),
            "cached_models": int(daemon_health.get("cached_models") or len(models)),
            "loaded_models": loaded_model_count,
            "models": models,
            "engines": engines_payload.get("engines", {}) if isinstance(engines_payload.get("engines"), dict) else {},
        }
        break

    _mlx_cache["status"] = normalized_status
    _mlx_cache["expires_at"] = now + MLX_CACHE_TTL_SECONDS
    return normalized_status
