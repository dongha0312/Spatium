from functools import partial
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Any

import anyio
import httpx
from fastapi import HTTPException
from gradio_client import Client, handle_file

from app.config import TEMP_DIR, settings


class HuggingFaceSpaceImageTo3DProvider:
    def __init__(self) -> None:
        if settings.huggingface_token:
            self.client = Client(settings.hf_space_id, hf_token=settings.huggingface_token)
        else:
            self.client = Client(settings.hf_space_id)

    async def generate(
        self,
        *,
        image_bytes: bytes,
        filename: str,
        content_type: str,
        mc_resolution: int,
        remove_background: bool,
        foreground_ratio: float,
    ) -> bytes:
        worker = partial(
            self._generate_sync,
            image_bytes=image_bytes,
            filename=filename,
            mc_resolution=mc_resolution,
            remove_background=remove_background,
            foreground_ratio=foreground_ratio,
        )
        return await anyio.to_thread.run_sync(worker)

    def _generate_sync(
        self,
        *,
        image_bytes: bytes,
        filename: str,
        mc_resolution: int,
        remove_background: bool,
        foreground_ratio: float,
    ) -> bytes:
        TEMP_DIR.mkdir(parents=True, exist_ok=True)
        suffix = Path(filename).suffix or ".png"

        with NamedTemporaryFile(dir=TEMP_DIR, suffix=suffix, delete=False) as image_file:
            image_file.write(image_bytes)
            image_path = image_file.name

        try:
            if settings.hf_space_id.lower() == "frogleo/image-to-3d":
                result = self.client.predict(
                    handle_file(image_path),
                    5,
                    5.5,
                    1234,
                    mc_resolution,
                    4000,
                    5000,
                    False,
                    api_name="/gen_shape",
                )
            else:
                processed_image = self.client.predict(
                    handle_file(image_path),
                    remove_background,
                    foreground_ratio,
                    api_name="/preprocess",
                )
                result = self.client.predict(
                    processed_image,
                    mc_resolution,
                    api_name="/generate",
                )
        except Exception as exc:
            raise HTTPException(
                status_code=502,
                detail={
                    "provider": "huggingface",
                    "space": settings.hf_space_id,
                    "message": str(exc),
                },
            ) from exc

        glb_result = self._pick_glb_result(result)
        return self._read_result_bytes(glb_result)

    def _pick_glb_result(self, result: Any) -> Any:
        if isinstance(result, (list, tuple)):
            for item in reversed(result):
                if self._looks_like_glb(item):
                    return item
            return result[-1]
        return result

    def _looks_like_glb(self, value: Any) -> bool:
        if isinstance(value, str):
            return value.lower().endswith(".glb")
        if isinstance(value, dict):
            return any(
                isinstance(value.get(key), str) and value[key].lower().endswith(".glb")
                for key in ("path", "url", "name")
            )
        return False

    def _read_result_bytes(self, result: Any) -> bytes:
        if isinstance(result, dict):
            for key in ("path", "url", "name"):
                value = result.get(key)
                if isinstance(value, str):
                    return self._read_result_bytes(value)

        if isinstance(result, str):
            path = Path(result)
            if path.exists():
                return path.read_bytes()
            if result.startswith(("http://", "https://")):
                response = httpx.get(result, timeout=180)
                response.raise_for_status()
                return response.content
            if result.startswith("/"):
                response = httpx.get(f"{self._space_base_url()}{result}", timeout=180)
                response.raise_for_status()
                return response.content

        raise HTTPException(
            status_code=502,
            detail={
                "provider": "huggingface",
                "message": "Could not read GLB result from Hugging Face Space.",
                "result": str(result),
            },
        )

    def _space_base_url(self) -> str:
        src = getattr(self.client, "src", "")
        if isinstance(src, str) and src.startswith(("http://", "https://")):
            return src.rstrip("/")

        subdomain = settings.hf_space_id.lower().replace("/", "-")
        return f"https://{subdomain}.hf.space"
