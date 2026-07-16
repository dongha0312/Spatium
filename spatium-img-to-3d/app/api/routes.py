from __future__ import annotations

import base64
import json
from secrets import compare_digest
from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, Header, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse
from starlette.background import BackgroundTask

from app.config import settings
from app.pipelines.image_to_3d import (
    GenerationOptions,
    GeneratedArtifact,
    ImageTo3DPipeline,
    RemoveBackgroundPipeline,
    SegmentationOptions,
)
from app.services.image_validation import ImageUploadValidator
from app.services.storage import StorageService


router = APIRouter()
INTERNAL_API_KEY_HEADER = "X-Internal-Api-Key"
AI_METADATA_HEADER = "X-Spatium-AI-Metadata"


def require_internal_api_key(
    supplied_key: Annotated[
        str | None,
        Header(alias=INTERNAL_API_KEY_HEADER),
    ] = None,
) -> None:
    expected_key = settings.internal_api_key
    if not expected_key:
        raise HTTPException(
            status_code=503,
            detail="Internal AI authentication is not configured.",
        )
    if supplied_key is None or not compare_digest(
        supplied_key.encode("utf-8"), expected_key.encode("utf-8")
    ):
        raise HTTPException(status_code=401, detail="Invalid internal API key.")


def artifact_response(
    artifact: GeneratedArtifact,
    storage: StorageService,
) -> FileResponse:
    metadata_json = json.dumps(
        artifact.metadata,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    metadata_header = base64.urlsafe_b64encode(metadata_json).decode("ascii").rstrip("=")
    return FileResponse(
        artifact.path,
        media_type=artifact.media_type,
        filename=artifact.download_name,
        headers={AI_METADATA_HEADER: metadata_header},
        background=BackgroundTask(storage.delete_artifact, artifact.path),
    )


def get_validator(request: Request) -> ImageUploadValidator:
    return request.app.state.image_validator


def get_image_to_3d_pipeline(request: Request) -> ImageTo3DPipeline:
    return request.app.state.image_to_3d_pipeline


def get_remove_background_pipeline(request: Request) -> RemoveBackgroundPipeline:
    return request.app.state.remove_background_pipeline


def get_storage(request: Request) -> StorageService:
    return request.app.state.storage


@router.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/v1/providers")
async def providers(
    _internal_api_key: None = Depends(require_internal_api_key),
) -> list[dict[str, str]]:
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
async def segmentation_providers(
    _internal_api_key: None = Depends(require_internal_api_key),
) -> list[dict[str, str]]:
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
    _internal_api_key: None = Depends(require_internal_api_key),
    validator: ImageUploadValidator = Depends(get_validator),
    pipeline: ImageTo3DPipeline = Depends(get_image_to_3d_pipeline),
    storage: StorageService = Depends(get_storage),
) -> FileResponse:
    validated = await validator.validate(image)
    artifact = await pipeline.generate(
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
    return artifact_response(artifact, storage)


@router.post("/v1/remove-background")
async def remove_background(
    image: UploadFile = File(...),
    segmentation_provider: str = Form("yolo"),
    target_class: str | None = Form(None),
    object_query: str | None = Form(None),
    _internal_api_key: None = Depends(require_internal_api_key),
    validator: ImageUploadValidator = Depends(get_validator),
    pipeline: RemoveBackgroundPipeline = Depends(get_remove_background_pipeline),
    storage: StorageService = Depends(get_storage),
) -> FileResponse:
    validated = await validator.validate(image)
    artifact = await pipeline.run(
        validated,
        SegmentationOptions(
            provider=segmentation_provider,
            target_class=target_class,
            object_query=object_query,
        ),
    )
    return artifact_response(artifact, storage)
