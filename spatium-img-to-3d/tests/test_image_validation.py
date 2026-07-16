from __future__ import annotations

import unittest
from io import BytesIO

from fastapi import HTTPException, UploadFile
from PIL import Image
from starlette.datastructures import Headers

from app.services.image_validation import ImageUploadValidator


def make_image(image_format: str = "PNG", size: tuple[int, int] = (4, 4)) -> bytes:
    output = BytesIO()
    Image.new("RGB", size, (20, 40, 60)).save(output, format=image_format)
    return output.getvalue()


def make_upload(data: bytes, content_type: str, filename: str = "image.png") -> UploadFile:
    return UploadFile(
        file=BytesIO(data),
        filename=filename,
        headers=Headers({"content-type": content_type}),
        size=len(data),
    )


class ImageUploadValidatorTests(unittest.IsolatedAsyncioTestCase):
    async def test_accepts_a_decodable_image_and_resets_pointer(self) -> None:
        data = make_image()
        upload = make_upload(data, "image/png")
        result = await ImageUploadValidator(max_bytes=1024, max_pixels=100).validate(upload)

        self.assertEqual(result.data, data)
        self.assertEqual(result.image_format, "PNG")
        self.assertEqual((result.width, result.height), (4, 4))
        self.assertEqual(await upload.read(), data)

    async def test_rejects_actual_bytes_over_limit_without_trusting_upload_size(self) -> None:
        upload = make_upload(make_image(), "image/png")
        upload.size = 1
        with self.assertRaises(HTTPException) as raised:
            await ImageUploadValidator(max_bytes=32, max_pixels=100).validate(upload)
        self.assertEqual(raised.exception.status_code, 413)

    async def test_rejects_media_type_disguised_as_png(self) -> None:
        upload = make_upload(make_image("JPEG"), "image/png")
        with self.assertRaises(HTTPException) as raised:
            await ImageUploadValidator(max_bytes=1024, max_pixels=100).validate(upload)
        self.assertEqual(raised.exception.status_code, 415)

    async def test_rejects_empty_or_corrupt_images(self) -> None:
        for data in (b"", b"not-an-image"):
            with self.subTest(data=data):
                upload = make_upload(data, "image/png")
                with self.assertRaises(HTTPException) as raised:
                    await ImageUploadValidator(max_bytes=1024, max_pixels=100).validate(upload)
                self.assertEqual(raised.exception.status_code, 422)

    async def test_rejects_excessive_pixel_count(self) -> None:
        upload = make_upload(make_image(size=(4, 4)), "image/png")
        with self.assertRaises(HTTPException) as raised:
            await ImageUploadValidator(max_bytes=1024, max_pixels=15).validate(upload)
        self.assertEqual(raised.exception.status_code, 413)
