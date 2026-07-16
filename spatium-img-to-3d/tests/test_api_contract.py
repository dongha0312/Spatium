from __future__ import annotations

import json
import struct
import unittest
from io import BytesIO
from pathlib import Path
from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient
from PIL import Image

from app.config import OUTPUT_DIR, PROCESSED_DIR
from app.main import app
from app.providers.local_triposr import LocalTripoSRProvider
from app.services.yolo_segmentation import SegmentationResult, YoloSegmentationService


def make_png(width: int = 8, height: int = 8) -> bytes:
    output = BytesIO()
    Image.new("RGB", (width, height), (120, 80, 40)).save(output, format="PNG")
    return output.getvalue()


def make_minimal_glb() -> bytes:
    document = {
        "asset": {"version": "2.0"},
        "scene": 0,
        "scenes": [{"nodes": []}],
        "nodes": [],
    }
    payload = json.dumps(document, separators=(",", ":")).encode("utf-8")
    payload += b" " * ((-len(payload)) % 4)
    body = struct.pack("<II", len(payload), 0x4E4F534A) + payload
    return struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body


class ApiContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.client_context = TestClient(app)
        self.client = self.client_context.__enter__()

    def tearDown(self) -> None:
        self.client_context.__exit__(None, None, None)

    def _cleanup_download(self, download_url: str) -> None:
        filename = Path(download_url).name
        if download_url.startswith("/v1/assets/"):
            (OUTPUT_DIR / filename).unlink(missing_ok=True)
        elif download_url.startswith("/v1/images/"):
            (PROCESSED_DIR / filename).unlink(missing_ok=True)

    def test_route_paths_and_methods_are_stable(self) -> None:
        routes = {
            path: {method.upper() for method in operations}
            for path, operations in app.openapi()["paths"].items()
        }
        expected = {
            "/": {"GET"},
            "/health": {"GET"},
            "/v1/providers": {"GET"},
            "/v1/segmentation-providers": {"GET"},
            "/v1/image-to-3d": {"POST"},
            "/v1/remove-background": {"POST"},
            "/v1/assets/{filename}": {"GET"},
            "/v1/images/{filename}": {"GET"},
        }
        for path, methods in expected.items():
            self.assertEqual(routes.get(path), methods)

    def test_health_response_contract(self) -> None:
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})

    def test_provider_response_contracts(self) -> None:
        providers = self.client.get("/v1/providers")
        self.assertEqual(providers.status_code, 200)
        self.assertEqual(
            providers.json(),
            [
                {
                    "id": "local_triposr",
                    "name": "Local TripoSR (GPU)",
                    "output": "glb",
                },
                {
                    "id": "local_stable_fast_3d",
                    "name": "Local Stable Fast 3D (GPU)",
                    "output": "glb",
                },
            ],
        )
        segmentation = self.client.get("/v1/segmentation-providers")
        self.assertEqual(segmentation.status_code, 200)
        self.assertEqual(
            segmentation.json(),
            [
                {"id": "yolo", "name": "YOLO segmentation", "query": "class"},
                {
                    "id": "grounded_sam2",
                    "name": "GroundingDINO + SAM2",
                    "query": "natural_language",
                },
            ],
        )

    def test_image_to_3d_success_response_contract(self) -> None:
        generate = AsyncMock(return_value=make_minimal_glb())
        with patch.object(LocalTripoSRProvider, "generate", generate):
            response = self.client.post(
                "/v1/image-to-3d",
                files={"image": ("chair.png", make_png(), "image/png")},
                data={
                    "provider": "local_triposr",
                    "remove_background": "false",
                    "mc_resolution": "256",
                },
            )

        self.assertEqual(response.status_code, 200, response.text)
        payload = response.json()
        self.addCleanup(self._cleanup_download, payload["download_url"])
        self.assertEqual(
            set(payload), {"id", "provider", "format", "download_url"}
        )
        self.assertEqual(payload["provider"], "local_triposr")
        self.assertEqual(payload["format"], "glb")
        self.assertEqual(payload["download_url"], f"/v1/assets/{payload['id']}.glb")

    def test_remove_background_success_response_contract(self) -> None:
        result = SegmentationResult(
            image_bytes=make_png(), detected_label="chair", device="cpu"
        )
        remove = AsyncMock(return_value=result)
        with patch.object(YoloSegmentationService, "remove_background", remove):
            response = self.client.post(
                "/v1/remove-background",
                files={"image": ("chair.png", make_png(), "image/png")},
                data={"segmentation_provider": "yolo", "target_class": "auto"},
            )

        self.assertEqual(response.status_code, 200, response.text)
        payload = response.json()
        self.addCleanup(self._cleanup_download, payload["download_url"])
        self.assertEqual(
            set(payload),
            {
                "id",
                "format",
                "segmentation_provider",
                "segmented_object",
                "device",
                "download_url",
            },
        )
        self.assertEqual(payload["segmented_object"], "chair")
        self.assertEqual(payload["download_url"], f"/v1/images/{payload['id']}.png")

    def test_unsupported_media_type_contract(self) -> None:
        response = self.client.post(
            "/v1/remove-background",
            files={"image": ("not-image.txt", b"not an image", "text/plain")},
        )
        self.assertEqual(response.status_code, 415)
        self.assertEqual(
            response.json(),
            {"detail": "Unsupported image type. Use PNG, JPEG, or WebP."},
        )

    def test_invalid_generation_provider_contract(self) -> None:
        response = self.client.post(
            "/v1/image-to-3d",
            files={"image": ("chair.png", make_png(), "image/png")},
            data={"provider": "unknown", "remove_background": "false"},
        )
        self.assertEqual(response.status_code, 422)
        self.assertEqual(
            response.json(),
            {
                "detail": (
                    "provider must be 'local_triposr' or "
                    "'local_stable_fast_3d'."
                )
            },
        )
