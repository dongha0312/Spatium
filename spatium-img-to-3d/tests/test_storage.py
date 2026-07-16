from __future__ import annotations

import json
import struct
import tempfile
import unittest
from io import BytesIO
from pathlib import Path

from fastapi import HTTPException
from PIL import Image

from app.services.storage import StorageService


def make_glb() -> bytes:
    payload = json.dumps({"asset": {"version": "2.0"}}).encode("utf-8")
    payload += b" " * ((-len(payload)) % 4)
    body = struct.pack("<II", len(payload), 0x4E4F534A) + payload
    return struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body


def make_png() -> bytes:
    output = BytesIO()
    Image.new("RGBA", (2, 2), (10, 20, 30, 255)).save(output, format="PNG")
    return output.getvalue()


class StorageServiceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.root_context = tempfile.TemporaryDirectory()
        root = Path(self.root_context.name)
        self.service = StorageService(
            output_dir=root / "outputs",
            processed_dir=root / "processed",
            temp_dir=root / "tmp",
        )
        self.service.ensure_directories()

    def tearDown(self) -> None:
        self.root_context.cleanup()

    def test_response_glb_and_png_can_be_deleted_after_streaming(self) -> None:
        asset_id, asset_path = self.service.save_glb(make_glb())
        image_id, image_path = self.service.save_png(make_png())

        self.assertTrue(asset_path.is_file())
        self.assertTrue(image_path.is_file())
        self.assertEqual(self.service.get_asset(f"{asset_id}.glb"), asset_path)
        self.assertEqual(self.service.get_processed_image(f"{image_id}.png"), image_path)
        self.assertEqual(list(self.service.output_dir.glob("*.tmp")), [])
        self.assertEqual(list(self.service.processed_dir.glob("*.tmp")), [])

        self.service.delete_artifact(asset_path)
        self.service.delete_artifact(image_path)
        self.assertFalse(asset_path.exists())
        self.assertFalse(image_path.exists())

    def test_artifact_cleanup_refuses_unmanaged_paths(self) -> None:
        outside = Path(self.root_context.name) / "outside.glb"
        outside.write_bytes(make_glb())

        self.service.delete_artifact(outside)

        self.assertTrue(outside.exists())

    def test_request_scoped_paths_are_removed_immediately(self) -> None:
        with self.service.temporary_file(suffix=".png") as path:
            path.write_bytes(b"temporary")
            self.assertTrue(path.exists())
        self.assertFalse(path.exists())

        with self.service.temporary_directory(prefix="provider-") as directory:
            nested = directory / "result.bin"
            nested.write_bytes(b"temporary")
            self.assertTrue(nested.exists())
        self.assertFalse(directory.exists())

    def test_rejects_traversal_and_wrong_extensions(self) -> None:
        for filename in ("../secret.glb", "folder/file.glb", "folder\\file.glb", "file.txt"):
            with self.subTest(filename=filename):
                with self.assertRaises(HTTPException) as raised:
                    self.service.get_asset(filename)
                self.assertEqual(raised.exception.status_code, 400)

    def test_rejects_structurally_corrupt_glb(self) -> None:
        corrupt = bytearray(make_glb())
        corrupt[20] = ord("x")
        with self.assertRaises(ValueError):
            self.service.save_glb(bytes(corrupt))
        self.assertEqual(list(self.service.output_dir.iterdir()), [])
