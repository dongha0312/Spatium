from __future__ import annotations

import logging
from dataclasses import dataclass
from io import BytesIO
from threading import Lock

import anyio
import numpy as np
from fastapi import HTTPException
from PIL import Image, ImageOps

from app.config import settings


logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class SegmentationResult:
    image_bytes: bytes
    detected_label: str
    device: str


class YoloSegmentationService:
    """Remove a photo background with a locally executed YOLO instance mask."""

    _model = None
    _model_lock = Lock()
    _CATEGORY_ALIASES = {
        "bed": "bed",
        "chair": "chair",
        "oven": "oven",
        "refrigerator": "refrigerator",
        "sink": "sink",
        "sofa": "couch",
        "table": "dining table",
        "television": "tv",
        "toilet": "toilet",
    }
    _UNSUPPORTED_CATEGORIES = {
        "bathhub",
        "bathtub",
        "dishwasher",
        "door",
        "storage",
        "stove",
        "washerdryer",
        "window",
    }

    async def remove_background(
        self,
        image_bytes: bytes,
        target_class: str | None = None,
    ) -> SegmentationResult:
        return await anyio.to_thread.run_sync(
            self._remove_background_sync,
            image_bytes,
            self._normalise_target(target_class),
        )

    def _remove_background_sync(
        self,
        image_bytes: bytes,
        target_class: str | None,
    ) -> SegmentationResult:
        try:
            with Image.open(BytesIO(image_bytes)) as opened:
                image = ImageOps.exif_transpose(opened).convert("RGB")
        except (OSError, ValueError) as exc:
            raise HTTPException(
                status_code=422,
                detail="YOLO input is not a readable image.",
            ) from exc

        source = np.asarray(image)
        device = self._device()

        try:
            result = self._get_model().predict(
                source=source,
                conf=settings.yolo_segmentation_confidence,
                device=device,
                retina_masks=True,
                verbose=False,
            )[0]
        except HTTPException:
            raise
        except Exception as exc:
            logger.exception("YOLO segmentation inference failed")
            raise HTTPException(
                status_code=502,
                detail={
                    "provider": "local-yolo-segmentation",
                    "message": "YOLO segmentation failed.",
                },
            ) from exc

        if result.masks is None or result.boxes is None or len(result.boxes) == 0:
            raise HTTPException(
                status_code=422,
                detail="No segmentable foreground object was found. Try a closer, clearer photo.",
            )

        index, label = self._select_instance(result, target_class, image.width, image.height)
        mask = result.masks.data[index].detach().cpu().numpy()
        alpha = Image.fromarray((mask > 0.5).astype(np.uint8) * 255, mode="L")
        alpha = alpha.resize(image.size, Image.Resampling.LANCZOS)

        output = image.convert("RGBA")
        output.putalpha(alpha)
        output = self._crop_to_foreground(output, alpha)
        output_bytes = BytesIO()
        output.save(output_bytes, format="PNG")

        return SegmentationResult(
            image_bytes=output_bytes.getvalue(),
            detected_label=label,
            device="cuda" if device != "cpu" else "cpu",
        )

    @classmethod
    def _get_model(cls):
        if cls._model is None:
            with cls._model_lock:
                if cls._model is None:
                    try:
                        from ultralytics import YOLO

                        cls._model = YOLO(settings.yolo_segmentation_model)
                    except Exception as exc:
                        logger.exception("Could not load YOLO model")
                        raise HTTPException(
                            status_code=503,
                            detail={
                                "provider": "local-yolo-segmentation",
                                "message": "Could not load YOLO model.",
                            },
                        ) from exc
        return cls._model

    @staticmethod
    def _normalise_target(target_class: str | None) -> str | None:
        if not target_class or target_class.lower() == "auto":
            return None
        category = target_class.strip().lower()
        if category in YoloSegmentationService._UNSUPPORTED_CATEGORIES:
            raise HTTPException(
                status_code=422,
                detail=(
                    f"'{target_class}' is not a class in the local YOLO11s-seg model. "
                    "Use auto or a supported category, or add a text-prompt segmentation model."
                ),
            )
        return YoloSegmentationService._CATEGORY_ALIASES.get(category, category)

    @staticmethod
    def _device() -> str | int:
        if settings.yolo_segmentation_device != "auto":
            return settings.yolo_segmentation_device
        try:
            import torch

            return 0 if torch.cuda.is_available() else "cpu"
        except ImportError:
            return "cpu"

    @staticmethod
    def _select_instance(result, target_class: str | None, width: int, height: int) -> tuple[int, str]:
        boxes = result.boxes
        labels = [str(result.names[int(class_id)]).lower() for class_id in boxes.cls.tolist()]
        candidates = list(range(len(labels)))
        if target_class:
            candidates = [index for index, label in enumerate(labels) if label == target_class]
            if not candidates:
                raise HTTPException(
                    status_code=422,
                    detail=f"YOLO did not find a '{target_class}' object in this photo.",
                )

        centre_x, centre_y = width / 2, height / 2
        index = max(
            candidates,
            key=lambda item: YoloSegmentationService._score(
                boxes.xyxy[item].tolist(),
                float(boxes.conf[item]),
                centre_x,
                centre_y,
                width,
                height,
            ),
        )
        return index, labels[index]

    @staticmethod
    def _score(
        box: list[float],
        confidence: float,
        centre_x: float,
        centre_y: float,
        width: int,
        height: int,
    ) -> float:
        left, top, right, bottom = box
        area = max(right - left, 0.0) * max(bottom - top, 0.0) / (width * height)
        box_centre_x, box_centre_y = (left + right) / 2, (top + bottom) / 2
        centre_distance = ((box_centre_x - centre_x) / width) ** 2 + (
            (box_centre_y - centre_y) / height
        ) ** 2
        return confidence * area * (1.0 - min(centre_distance, 0.8))

    @staticmethod
    def _crop_to_foreground(image: Image.Image, alpha: Image.Image) -> Image.Image:
        bounds = alpha.getbbox()
        if bounds is None:
            raise HTTPException(status_code=422, detail="YOLO created an empty foreground mask.")

        left, top, right, bottom = bounds
        padding = max(16, round(max(right - left, bottom - top) * 0.1))
        return image.crop(
            (
                max(0, left - padding),
                max(0, top - padding),
                min(image.width, right + padding),
                min(image.height, bottom + padding),
            )
        )
