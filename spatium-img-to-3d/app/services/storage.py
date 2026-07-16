from __future__ import annotations

import json
import os
import struct
from contextlib import contextmanager
from io import BytesIO
from pathlib import Path
from tempfile import NamedTemporaryFile, TemporaryDirectory
from typing import Iterator
from uuid import uuid4

from fastapi import HTTPException
from PIL import Image, UnidentifiedImageError

from app.config import OUTPUT_DIR, PROCESSED_DIR, TEMP_DIR


class StorageService:
    """Own final artifact writes and request-scoped temporary paths.

    Final GLB and PNG files are intentionally retained. Only request-scoped
    temporary files and run directories are removed automatically.
    """

    def __init__(
        self,
        *,
        output_dir: Path = OUTPUT_DIR,
        processed_dir: Path = PROCESSED_DIR,
        temp_dir: Path = TEMP_DIR,
    ) -> None:
        self.output_dir = output_dir
        self.processed_dir = processed_dir
        self.temp_dir = temp_dir

    def ensure_directories(self) -> None:
        for directory in (self.output_dir, self.processed_dir, self.temp_dir):
            directory.mkdir(parents=True, exist_ok=True)

    def save_glb(self, data: bytes) -> tuple[str, Path]:
        self._validate_glb(data)
        asset_id = uuid4().hex
        path = self.output_dir / f"{asset_id}.glb"
        self._atomic_write(path, data)
        return asset_id, path

    def save_png(self, data: bytes) -> tuple[str, Path]:
        self._validate_png(data)
        image_id = uuid4().hex
        path = self.processed_dir / f"{image_id}.png"
        self._atomic_write(path, data)
        return image_id, path

    def get_asset(self, filename: str) -> Path:
        return self._resolve_final_file(self.output_dir, filename, ".glb", "asset")

    def get_processed_image(self, filename: str) -> Path:
        return self._resolve_final_file(self.processed_dir, filename, ".png", "image")

    @contextmanager
    def temporary_file(self, *, suffix: str) -> Iterator[Path]:
        self.temp_dir.mkdir(parents=True, exist_ok=True)
        with NamedTemporaryFile(dir=self.temp_dir, suffix=suffix, delete=False) as handle:
            path = Path(handle.name)
        try:
            yield path
        finally:
            path.unlink(missing_ok=True)

    @contextmanager
    def temporary_directory(self, *, prefix: str) -> Iterator[Path]:
        self.temp_dir.mkdir(parents=True, exist_ok=True)
        with TemporaryDirectory(dir=self.temp_dir, prefix=prefix) as directory:
            yield Path(directory)

    @staticmethod
    def _validate_glb(data: bytes) -> None:
        if len(data) < 20:
            raise ValueError("Generated GLB is empty or incomplete.")
        magic, version, declared_length = struct.unpack_from("<4sII", data, 0)
        if magic != b"glTF" or version != 2 or declared_length != len(data):
            raise ValueError("Generated output is not a valid GLB 2.0 file.")

        offset = 12
        chunk_index = 0
        while offset < len(data):
            if offset + 8 > len(data):
                raise ValueError("Generated GLB has an incomplete chunk header.")
            chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
            offset += 8
            chunk_end = offset + chunk_length
            if chunk_length % 4 != 0 or chunk_end > len(data):
                raise ValueError("Generated GLB has an invalid chunk payload.")
            payload = data[offset:chunk_end]
            if chunk_index == 0:
                if chunk_type != 0x4E4F534A:
                    raise ValueError("Generated GLB is missing its JSON chunk.")
                try:
                    document = json.loads(
                        payload.rstrip(b" \t\r\n\x00").decode("utf-8")
                    )
                except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                    raise ValueError("Generated GLB has invalid JSON metadata.") from exc
                if not isinstance(document, dict) or "asset" not in document:
                    raise ValueError("Generated GLB metadata is incomplete.")
            offset = chunk_end
            chunk_index += 1
        if chunk_index == 0 or offset != len(data):
            raise ValueError("Generated GLB has no readable chunks.")

    @staticmethod
    def _validate_png(data: bytes) -> None:
        try:
            with Image.open(BytesIO(data)) as image:
                if image.format != "PNG":
                    raise ValueError("Processed image is not PNG data.")
                image.verify()
        except (UnidentifiedImageError, OSError) as exc:
            raise ValueError("Processed image is not a readable PNG.") from exc

    @staticmethod
    def _atomic_write(path: Path, data: bytes) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        temp_path: Path | None = None
        try:
            with NamedTemporaryFile(
                dir=path.parent,
                prefix=f".{path.name}.",
                suffix=".tmp",
                delete=False,
            ) as handle:
                temp_path = Path(handle.name)
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temp_path, path)
        finally:
            if temp_path is not None:
                temp_path.unlink(missing_ok=True)

    @staticmethod
    def _resolve_final_file(
        directory: Path, filename: str, suffix: str, kind: str
    ) -> Path:
        if (
            Path(filename).name != filename
            or "/" in filename
            or "\\" in filename
            or not filename.lower().endswith(suffix)
        ):
            raise HTTPException(status_code=400, detail=f"Invalid {kind} filename.")
        path = directory / filename
        if not path.is_file():
            label = "Asset" if kind == "asset" else "Image"
            raise HTTPException(status_code=404, detail=f"{label} not found.")
        return path
