from __future__ import annotations

import logging
from dataclasses import dataclass
from functools import partial
from pathlib import Path
from typing import Any

import anyio
from fastapi import HTTPException

from app.config import settings
from app.providers.local_stable_fast_3d import LocalStableFast3DProvider
from app.providers.local_triposr import LocalTripoSRProvider
from app.services.concurrency import GpuConcurrencyLimiter
from app.services.glb_orientation import orient_glb_for_threejs
from app.services.image_validation import ValidatedImage
from app.services.segmentation import SegmentationService
from app.services.storage import StorageService


logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class GenerationOptions:
    foreground_ratio: float | None
    mc_resolution: int
    remove_background: bool
    background_removal: str
    segmentation_provider: str | None
    target_class: str | None
    object_query: str | None
    provider: str
    texture_resolution: int
    remesh: str


@dataclass(frozen=True)
class SegmentationOptions:
    provider: str
    target_class: str | None
    object_query: str | None


@dataclass(frozen=True)
class GeneratedArtifact:
    path: Path
    media_type: str
    download_name: str
    metadata: dict[str, Any]


class ImageTo3DPipeline:
    def __init__(
        self,
        *,
        triposr: LocalTripoSRProvider,
        stable_fast_3d: LocalStableFast3DProvider,
        segmentation: SegmentationService,
        storage: StorageService,
        gpu_limiter: GpuConcurrencyLimiter,
    ) -> None:
        self.providers = {
            "local_triposr": triposr,
            "local_stable_fast_3d": stable_fast_3d,
        }
        self.segmentation = segmentation
        self.storage = storage
        self.gpu_limiter = gpu_limiter

    async def generate(
        self, image: ValidatedImage, options: GenerationOptions
    ) -> GeneratedArtifact:
        provider_name = options.provider.strip().lower()
        provider = self.providers.get(provider_name)
        if provider is None:
            raise HTTPException(
                status_code=422,
                detail=(
                    "provider must be 'local_triposr' or "
                    "'local_stable_fast_3d'."
                ),
            )

        image_bytes = image.data
        filename = image.filename
        content_type = image.content_type
        run_provider_background_removal = options.remove_background
        segmented_object: str | None = None
        translated_query: str | None = None
        segmentation_name = self._selected_segmentation(options)

        async with self.gpu_limiter.slot():
            if options.remove_background and segmentation_name:
                segmented = await self.segmentation.remove_background(
                    image_bytes=image_bytes,
                    provider=segmentation_name,
                    target_class=options.target_class,
                    object_query=options.object_query,
                )
                image_bytes = segmented.image_bytes
                filename = "segmented.png"
                content_type = "image/png"
                segmented_object = segmented.detected_label
                translated_query = getattr(segmented, "translated_query", None)
                run_provider_background_removal = False

            foreground_ratio = options.foreground_ratio or 0.85
            if provider_name == "local_triposr":
                output_bytes = await provider.generate(
                    image_bytes=image_bytes,
                    filename=filename,
                    content_type=content_type,
                    mc_resolution=options.mc_resolution,
                    remove_background=run_provider_background_removal,
                    foreground_ratio=foreground_ratio,
                )
            else:
                output_bytes = await provider.generate(
                    image_bytes=image_bytes,
                    filename=filename,
                    texture_resolution=options.texture_resolution,
                    remesh=options.remesh.strip().lower(),
                    foreground_ratio=foreground_ratio,
                )

        if settings.auto_orient_glb_for_threejs:
            try:
                orient = partial(
                    orient_glb_for_threejs,
                    rotation_x_degrees=settings.glb_rotation_x_degrees,
                )
                output_bytes = await anyio.to_thread.run_sync(orient, output_bytes)
            except (ValueError, TypeError) as exc:
                logger.exception("Generated GLB could not be oriented")
                raise HTTPException(
                    status_code=502,
                    detail="The generated GLB file is invalid.",
                ) from exc

        try:
            _asset_id, output_path = await anyio.to_thread.run_sync(
                self.storage.save_glb, output_bytes
            )
        except (OSError, ValueError) as exc:
            logger.exception("Generated GLB could not be stored")
            raise HTTPException(
                status_code=500,
                detail="The generated GLB file could not be stored.",
            ) from exc

        metadata: dict[str, Any] = {
            "provider": provider_name,
        }
        if segmented_object:
            metadata["segmented_object"] = segmented_object
        if segmentation_name:
            metadata["segmentation_provider"] = segmentation_name
        if translated_query:
            metadata["translated_query"] = translated_query
        return GeneratedArtifact(
            path=output_path,
            media_type="model/gltf-binary",
            download_name="generated-model.glb",
            metadata=metadata,
        )

    @staticmethod
    def _selected_segmentation(options: GenerationOptions) -> str | None:
        if not options.remove_background:
            return None
        selected = (options.segmentation_provider or options.background_removal).strip().lower()
        if selected == "none":
            return None
        return selected or None


class RemoveBackgroundPipeline:
    def __init__(
        self,
        *,
        segmentation: SegmentationService,
        storage: StorageService,
        gpu_limiter: GpuConcurrencyLimiter,
    ) -> None:
        self.segmentation = segmentation
        self.storage = storage
        self.gpu_limiter = gpu_limiter

    async def run(
        self, image: ValidatedImage, options: SegmentationOptions
    ) -> GeneratedArtifact:
        provider_name = options.provider.strip().lower()
        async with self.gpu_limiter.slot():
            result = await self.segmentation.remove_background(
                image_bytes=image.data,
                provider=provider_name,
                target_class=options.target_class,
                object_query=options.object_query,
            )

        try:
            _image_id, output_path = await anyio.to_thread.run_sync(
                self.storage.save_png, result.image_bytes
            )
        except (OSError, ValueError) as exc:
            logger.exception("Segmented PNG could not be stored")
            raise HTTPException(
                status_code=500,
                detail="The processed image could not be stored.",
            ) from exc

        metadata: dict[str, Any] = {
            "segmentation_provider": provider_name,
            "segmented_object": result.detected_label,
            "device": result.device,
        }
        translated_query = getattr(result, "translated_query", None)
        confidence = getattr(result, "confidence", None)
        if translated_query:
            metadata["translated_query"] = translated_query
        if confidence is not None:
            metadata["confidence"] = round(float(confidence), 4)
        return GeneratedArtifact(
            path=output_path,
            media_type="image/png",
            download_name="segmented.png",
            metadata=metadata,
        )
