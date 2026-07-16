from __future__ import annotations

from fastapi import HTTPException

from app.services.grounded_sam2 import GroundedSam2Service
from app.services.yolo_segmentation import YoloSegmentationService


class SegmentationService:
    def __init__(
        self,
        *,
        yolo: YoloSegmentationService | None = None,
        grounded_sam2: GroundedSam2Service | None = None,
    ) -> None:
        self.yolo = yolo or YoloSegmentationService()
        self.grounded_sam2 = grounded_sam2 or GroundedSam2Service()

    async def remove_background(
        self,
        *,
        image_bytes: bytes,
        provider: str,
        target_class: str | None,
        object_query: str | None,
    ):
        if provider == "yolo":
            return await self.yolo.remove_background(image_bytes, target_class)
        if provider == "grounded_sam2":
            return await self.grounded_sam2.remove_background(image_bytes, object_query or "")
        raise HTTPException(
            status_code=422,
            detail="segmentation_provider must be 'yolo' or 'grounded_sam2'.",
        )
