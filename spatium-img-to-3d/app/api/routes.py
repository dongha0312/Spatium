from __future__ import annotations

from fastapi import APIRouter, Depends, File, Form, Request, UploadFile
from fastapi.responses import FileResponse, HTMLResponse

from app.config import settings
from app.pipelines.image_to_3d import (
    GenerationOptions,
    ImageTo3DPipeline,
    RemoveBackgroundPipeline,
    SegmentationOptions,
)
from app.services.image_validation import ImageUploadValidator
from app.services.storage import StorageService
from app.ui import INDEX_HTML


router = APIRouter()


def get_validator(request: Request) -> ImageUploadValidator:
    return request.app.state.image_validator


def get_image_to_3d_pipeline(request: Request) -> ImageTo3DPipeline:
    return request.app.state.image_to_3d_pipeline


def get_remove_background_pipeline(request: Request) -> RemoveBackgroundPipeline:
    return request.app.state.remove_background_pipeline


def get_storage(request: Request) -> StorageService:
    return request.app.state.storage


@router.get("/", response_class=HTMLResponse)
async def index() -> str:
    return INDEX_HTML


@router.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/v1/providers")
async def providers() -> list[dict[str, str]]:
    return [
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
    ]


@router.get("/v1/segmentation-providers")
async def segmentation_providers() -> list[dict[str, str]]:
    return [
        {"id": "yolo", "name": "YOLO segmentation", "query": "class"},
        {
            "id": "grounded_sam2",
            "name": "GroundingDINO + SAM2",
            "query": "natural_language",
        },
    ]


@router.post("/v1/image-to-3d")
async def image_to_3d(
    image: UploadFile = File(...),
    foreground_ratio: float | None = Form(None),
    mc_resolution: int = Form(256),
    remove_background: bool = Form(True),
    background_removal: str = Form("yolo"),
    segmentation_provider: str | None = Form(None),
    target_class: str | None = Form(None),
    object_query: str | None = Form(None),
    provider: str = Form(settings.image_to_3d_provider),
    texture_resolution: int = Form(1024),
    remesh: str = Form("none"),
    validator: ImageUploadValidator = Depends(get_validator),
    pipeline: ImageTo3DPipeline = Depends(get_image_to_3d_pipeline),
) -> dict[str, str]:
    validated = await validator.validate(image)
    return await pipeline.generate(
        validated,
        GenerationOptions(
            foreground_ratio=foreground_ratio,
            mc_resolution=mc_resolution,
            remove_background=remove_background,
            background_removal=background_removal,
            segmentation_provider=segmentation_provider,
            target_class=target_class,
            object_query=object_query,
            provider=provider,
            texture_resolution=texture_resolution,
            remesh=remesh,
        ),
    )


@router.post("/v1/remove-background")
async def remove_background(
    image: UploadFile = File(...),
    segmentation_provider: str = Form("yolo"),
    target_class: str | None = Form(None),
    object_query: str | None = Form(None),
    validator: ImageUploadValidator = Depends(get_validator),
    pipeline: RemoveBackgroundPipeline = Depends(get_remove_background_pipeline),
) -> dict[str, str]:
    validated = await validator.validate(image)
    return await pipeline.run(
        validated,
        SegmentationOptions(
            provider=segmentation_provider,
            target_class=target_class,
            object_query=object_query,
        ),
    )


@router.get("/v1/assets/{filename}")
async def download_asset(
    filename: str, storage: StorageService = Depends(get_storage)
) -> FileResponse:
    path = storage.get_asset(filename)
    return FileResponse(
        path,
        media_type="model/gltf-binary",
        filename=filename,
    )


@router.get("/v1/images/{filename}")
async def download_processed_image(
    filename: str, storage: StorageService = Depends(get_storage)
) -> FileResponse:
    path = storage.get_processed_image(filename)
    return FileResponse(path, media_type="image/png", filename=filename)
