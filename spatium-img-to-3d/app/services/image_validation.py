from __future__ import annotations

from dataclasses import dataclass
from io import BytesIO

from fastapi import HTTPException, UploadFile
from PIL import Image, UnidentifiedImageError


ALLOWED_IMAGE_TYPES = {
    "image/png": {"PNG"},
    "image/jpeg": {"JPEG"},
    "image/webp": {"WEBP"},
}
FORMAT_SUFFIXES = {"PNG": ".png", "JPEG": ".jpg", "WEBP": ".webp"}
READ_CHUNK_BYTES = 1024 * 1024


@dataclass(frozen=True)
class ValidatedImage:
    data: bytes
    filename: str
    content_type: str
    width: int
    height: int
    image_format: str


class ImageUploadValidator:
    def __init__(self, *, max_bytes: int, max_pixels: int) -> None:
        self.max_bytes = max_bytes
        self.max_pixels = max_pixels

    async def validate(self, upload: UploadFile) -> ValidatedImage:
        content_type = (upload.content_type or "").lower()
        if content_type not in ALLOWED_IMAGE_TYPES:
            raise HTTPException(
                status_code=415,
                detail="Unsupported image type. Use PNG, JPEG, or WebP.",
            )

        chunks: list[bytes] = []
        size = 0
        try:
            while chunk := await upload.read(READ_CHUNK_BYTES):
                size += len(chunk)
                if size > self.max_bytes:
                    raise HTTPException(
                        status_code=413,
                        detail="Image is larger than MAX_UPLOAD_BYTES.",
                    )
                chunks.append(chunk)
        finally:
            await upload.seek(0)

        if size == 0:
            raise HTTPException(status_code=422, detail="Uploaded image is empty.")

        data = b"".join(chunks)
        try:
            with Image.open(BytesIO(data)) as decoded:
                image_format = (decoded.format or "").upper()
                width, height = decoded.size
                if width <= 0 or height <= 0:
                    raise HTTPException(status_code=422, detail="Image dimensions are invalid.")
                if width * height > self.max_pixels:
                    raise HTTPException(
                        status_code=413,
                        detail="Image resolution is larger than MAX_IMAGE_PIXELS.",
                    )
                decoded.verify()
        except HTTPException:
            raise
        except (Image.DecompressionBombError, Image.DecompressionBombWarning) as exc:
            raise HTTPException(
                status_code=413,
                detail="Image resolution is too large.",
            ) from exc
        except (UnidentifiedImageError, OSError, ValueError) as exc:
            raise HTTPException(
                status_code=422,
                detail="Uploaded file is not a readable image.",
            ) from exc

        if image_format not in ALLOWED_IMAGE_TYPES[content_type]:
            raise HTTPException(
                status_code=415,
                detail="Image content does not match its declared media type.",
            )

        suffix = FORMAT_SUFFIXES[image_format]
        return ValidatedImage(
            data=data,
            filename=f"image{suffix}",
            content_type=content_type,
            width=width,
            height=height,
            image_format=image_format,
        )
