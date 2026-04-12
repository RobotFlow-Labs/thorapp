"""Unified stream catalog and pull-based preview endpoints."""

import base64
from fastapi import APIRouter, HTTPException
from fastapi.responses import Response
from sim import (
    active_camera_bridges,
    is_sim,
    sim_laserscan_frame,
    sim_stream_catalog,
    sim_stream_health,
)

router = APIRouter(prefix="/v1/streams", tags=["streams"])

_PLACEHOLDER_JPEG_BASE64 = (
    "/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAAB"
    "AAEAAKACAAQAAAABAAAAAqADAAQAAAABAAAAAgAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklN"
    "BCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgAAgACAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAAB"
    "AgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNi"
    "coIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SV"
    "lpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8B"
    "AAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXET"
    "IjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpz"
    "dHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm"
    "5+jp6vLz9PX29/j5+v/bAEMAAgICAgICAwICAwUDAwMFBgUFBQUGCAYGBgYGCAoICAgICAgKCgoKCgoKCgwMDAwM"
    "DA4ODg4ODw8PDw8PDw8PD//bAEMBAgICBAQEBwQEBxALCQsQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQ"
    "EBAQEBAQEBAQEBAQEBAQEBAQEP/dAAQAAf/aAAwDAQACEQMRAD8A/XCiiigD/9k="
)


def _catalog_entry(source_id: str) -> dict | None:
    for stream in sim_stream_catalog():
        if stream["id"] == source_id:
            return stream
    return None


@router.get("/catalog")
async def stream_catalog():
    """List known image and scan sources."""
    if is_sim():
        streams = sim_stream_catalog()
        return {"streams": streams, "count": len(streams)}

    return {"streams": [], "count": 0}


@router.get("/health/{source_id}")
async def stream_health(source_id: str):
    """Return current transport/source health for a stream."""
    if is_sim():
        if not _catalog_entry(source_id):
            raise HTTPException(status_code=404, detail="stream not found")
        return {"health": sim_stream_health(source_id)}

    raise HTTPException(status_code=404, detail="stream not found")


@router.get("/image/{source_id}/latest.jpg")
async def latest_stream_image(source_id: str):
    """Return the latest JPEG frame for an image stream."""
    if is_sim():
        if not _catalog_entry(source_id):
            raise HTTPException(status_code=404, detail="stream not found")

        bridge = active_camera_bridges(max_age_seconds=30).get(source_id)
        if bridge and bridge.get("frame_bytes"):
            payload = bridge["frame_bytes"]
        else:
            payload = base64.b64decode(_PLACEHOLDER_JPEG_BASE64)

        return Response(
            content=payload,
            media_type="image/jpeg",
            headers={"Cache-Control": "no-store, max-age=0"},
        )

    raise HTTPException(status_code=404, detail="stream not found")


@router.get("/scan/{source_id}/latest")
async def latest_stream_scan(source_id: str):
    """Return the latest LaserScan frame for a scan stream."""
    if is_sim():
        entry = _catalog_entry(source_id)
        if not entry or entry.get("kind") != "scan":
            raise HTTPException(status_code=404, detail="scan stream not found")
        return {"scan": sim_laserscan_frame(source_id), "metadata": sim_stream_health(source_id)}

    raise HTTPException(status_code=404, detail="scan stream not found")
