from __future__ import annotations

import base64
import json
import struct
import unittest
from io import BytesIO
from unittest.mock import AsyncMock, patch
from uuid import uuid4

from fastapi.testclient import TestClient
from PIL import Image

from app.api.routes import AI_METADATA_HEADER, INTERNAL_API_KEY_HEADER
from app.config import OUTPUT_DIR, PROCESSED_DIR, settings
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
        self.original_api_key = settings.internal_api_key
        self.api_key = uuid4().hex
        settings.internal_api_key = self.api_key
        self.auth_headers = {INTERNAL_API_KEY_HEADER: self.api_key}
        self.client_context = TestClient(app)
        self.client = self.client_context.__enter__()

    def tearDown(self) -> None:
        self.client_context.__exit__(None, None, None)
        settings.internal_api_key = self.original_api_key

    @staticmethod
    def _decode_metadata(response) -> dict[str, object]:
        encoded = response.headers[AI_METADATA_HEADER]
        padded = encoded + "=" * (-len(encoded) % 4)
        return json.loads(base64.urlsafe_b64decode(padded).decode("utf-8"))

    def test_route_paths_and_methods_are_stable(self) -> None:
        routes = {
            path: {method.upper() for method in operations}
            for path, operations in app.openapi()["paths"].items()
        }
        expected = {
            "/health": {"GET"},
            "/v1/providers": {"GET"},
            "/v1/segmentation-providers": {"GET"},
            "/v1/image-to-3d": {"POST"},
            "/v1/remove-background": {"POST"},
        }
        self.assertEqual(routes, expected)

    def test_health_response_contract(self) -> None:
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})

    def test_provider_response_contracts(self) -> None:
        providers = self.client.get("/v1/providers", headers=self.auth_headers)
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
        segmentation = self.client.get(
            "/v1/segmentation-providers", headers=self.auth_headers
        )
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
        existing_outputs = set(OUTPUT_DIR.glob("*.glb"))
        generate = AsyncMock(return_value=make_minimal_glb())
        with patch.object(LocalTripoSRProvider, "generate", generate):
            response = self.client.post(
                "/v1/image-to-3d",
                headers=self.auth_headers,
                files={"image": ("chair.png", make_png(), "image/png")},
                data={
                    "provider": "local_triposr",
                    "remove_background": "false",
                    "mc_resolution": "256",
                },
            )

        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.headers["content-type"], "model/gltf-binary")
        self.assertIn("generated-model.glb", response.headers["content-disposition"])
        self.assertEqual(response.content[:4], b"glTF")
        self.assertEqual(
            self._decode_metadata(response), {"provider": "local_triposr"}
        )
        self.assertEqual(set(OUTPUT_DIR.glob("*.glb")), existing_outputs)

    def test_remove_background_success_response_contract(self) -> None:
        existing_images = set(PROCESSED_DIR.glob("*.png"))
        result = SegmentationResult(
            image_bytes=make_png(), detected_label="chair", device="cpu"
        )
        remove = AsyncMock(return_value=result)
        with patch.object(YoloSegmentationService, "remove_background", remove):
            response = self.client.post(
                "/v1/remove-background",
                headers=self.auth_headers,
                files={"image": ("chair.png", make_png(), "image/png")},
                data={"segmentation_provider": "yolo", "target_class": "auto"},
            )

        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.headers["content-type"], "image/png")
        self.assertTrue(response.content.startswith(b"\x89PNG\r\n\x1a\n"))
        metadata = self._decode_metadata(response)
        self.assertEqual(metadata["segmented_object"], "chair")
        self.assertEqual(metadata["segmentation_provider"], "yolo")
        self.assertEqual(metadata["device"], "cpu")
        self.assertEqual(set(PROCESSED_DIR.glob("*.png")), existing_images)

    def test_ai_routes_require_the_internal_api_key(self) -> None:
        files = {"image": ("chair.png", make_png(), "image/png")}
        missing = self.client.post("/v1/remove-background", files=files)
        self.assertEqual(missing.status_code, 401)

        wrong = self.client.post(
            "/v1/remove-background",
            headers={INTERNAL_API_KEY_HEADER: "wrong"},
            files=files,
        )
        self.assertEqual(wrong.status_code, 401)

    def test_unsupported_media_type_contract(self) -> None:
        response = self.client.post(
            "/v1/remove-background",
            headers=self.auth_headers,
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
            headers=self.auth_headers,
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
