from __future__ import annotations

import json
import math
import struct


GLB_MAGIC = b"glTF"
GLB_VERSION = 2
JSON_CHUNK_TYPE = 0x4E4F534A
AXIS_NODE_NAME = "SpatiumThreeJsAxisCorrection"


def orient_glb_for_threejs(glb: bytes, rotation_x_degrees: float = -90.0) -> bytes:
    """Add a root X-axis rotation without re-encoding meshes or textures."""
    if abs(rotation_x_degrees) < 1e-9:
        return glb
    if len(glb) < 20:
        raise ValueError("Generated GLB is too short.")

    magic, version, declared_length = struct.unpack_from("<4sII", glb, 0)
    if magic != GLB_MAGIC or version != GLB_VERSION or declared_length != len(glb):
        raise ValueError("Generated file is not a valid GLB 2.0 document.")

    chunks: list[tuple[int, bytes]] = []
    offset = 12
    while offset < len(glb):
        if offset + 8 > len(glb):
            raise ValueError("Generated GLB has an incomplete chunk header.")
        chunk_length, chunk_type = struct.unpack_from("<II", glb, offset)
        offset += 8
        end = offset + chunk_length
        if end > len(glb):
            raise ValueError("Generated GLB has an incomplete chunk payload.")
        chunks.append((chunk_type, glb[offset:end]))
        offset = end

    if not chunks or chunks[0][0] != JSON_CHUNK_TYPE:
        raise ValueError("Generated GLB is missing its JSON chunk.")

    document = json.loads(chunks[0][1].rstrip(b" \t\r\n\x00").decode("utf-8"))
    nodes = document.setdefault("nodes", [])
    scenes = document.get("scenes")
    if not scenes:
        child_nodes = {
            child
            for node in nodes
            for child in node.get("children", [])
            if isinstance(child, int)
        }
        root_nodes = [index for index in range(len(nodes)) if index not in child_nodes]
        scenes = [{"nodes": root_nodes}]
        document["scenes"] = scenes
        document["scene"] = 0

    angle = math.radians(rotation_x_degrees)
    rotation = [math.sin(angle / 2.0), 0.0, 0.0, math.cos(angle / 2.0)]
    for scene in scenes:
        original_roots = list(scene.get("nodes", []))
        wrapper_index = len(nodes)
        nodes.append(
            {
                "name": AXIS_NODE_NAME,
                "rotation": rotation,
                "children": original_roots,
                "extras": {
                    "axisCorrection": "Three.js Y-up",
                    "rotationXDegrees": rotation_x_degrees,
                },
            }
        )
        scene["nodes"] = [wrapper_index]

    json_payload = json.dumps(
        document, ensure_ascii=False, separators=(",", ":")
    ).encode("utf-8")
    json_payload += b" " * ((-len(json_payload)) % 4)
    chunks[0] = (JSON_CHUNK_TYPE, json_payload)

    body = b"".join(
        struct.pack("<II", len(payload), chunk_type) + payload
        for chunk_type, payload in chunks
    )
    return struct.pack("<4sII", GLB_MAGIC, GLB_VERSION, 12 + len(body)) + body
