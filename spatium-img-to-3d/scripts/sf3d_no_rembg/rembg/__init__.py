"""Minimal rembg replacement for already-segmented RGBA inputs.

Stable Fast 3D's upstream runner always imports rembg and creates a session,
even though its preprocessing skips removal when the image already has a
non-opaque alpha channel. This stub avoids loading ONNX Runtime in that path.
"""


def new_session(*args, **kwargs):
    return None


def remove(*args, **kwargs):
    raise RuntimeError(
        "rembg is disabled: provide the transparent PNG produced by YOLO segmentation."
    )
