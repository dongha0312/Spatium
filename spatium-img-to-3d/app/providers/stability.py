import httpx
from fastapi import HTTPException

from app.config import settings


class StabilityImageTo3DProvider:
    endpoint = "/v2beta/3d/stable-fast-3d"

    async def generate(
        self,
        *,
        image_bytes: bytes,
        filename: str,
        content_type: str,
        texture_resolution: int,
        remesh: str,
        foreground_ratio: float | None,
    ) -> bytes:
        if not settings.stability_api_key:
            raise HTTPException(
                status_code=500,
                detail="STABILITY_API_KEY is not configured.",
            )

        data: dict[str, str] = {
            "texture_resolution": str(texture_resolution),
            "remesh": remesh,
        }
        if foreground_ratio is not None:
            data["foreground_ratio"] = str(foreground_ratio)

        files = {
            "image": (filename, image_bytes, content_type),
        }
        headers = {
            "Authorization": f"Bearer {settings.stability_api_key}",
            "Accept": "model/gltf-binary",
        }

        async with httpx.AsyncClient(timeout=180) as client:
            response = await client.post(
                f"{settings.stability_base_url}{self.endpoint}",
                headers=headers,
                data=data,
                files=files,
            )

        if response.status_code >= 400:
            raise HTTPException(
                status_code=502,
                detail={
                    "provider": "stability",
                    "status_code": response.status_code,
                    "message": response.text,
                },
            )

        if not response.content:
            raise HTTPException(
                status_code=502,
                detail="Stability API returned an empty response.",
            )

        return response.content
