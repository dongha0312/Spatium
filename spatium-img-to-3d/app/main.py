from __future__ import annotations

import logging
import re
from contextlib import asynccontextmanager
from time import perf_counter
from uuid import uuid4

from fastapi import FastAPI, Request

from app.api.routes import router
from app.config import settings
from app.logging_config import configure_logging
from app.pipelines.image_to_3d import ImageTo3DPipeline, RemoveBackgroundPipeline
from app.providers.local_stable_fast_3d import LocalStableFast3DProvider
from app.providers.local_triposr import LocalTripoSRProvider
from app.services.concurrency import GpuConcurrencyLimiter
from app.services.grounded_sam2 import GroundedSam2Service
from app.services.image_validation import ImageUploadValidator
from app.services.process_runner import AsyncProcessRunner
from app.services.segmentation import SegmentationService
from app.services.storage import StorageService
from app.services.yolo_segmentation import YoloSegmentationService


configure_logging()
logger = logging.getLogger(__name__)
REQUEST_ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{1,64}$")


@asynccontextmanager
async def lifespan(application: FastAPI):
    storage = StorageService()
    storage.ensure_directories()
    runner = AsyncProcessRunner()
    gpu_limiter = GpuConcurrencyLimiter(settings.gpu_max_concurrency)
    yolo = YoloSegmentationService()
    grounded_sam2 = GroundedSam2Service(runner=runner, storage=storage)
    segmentation = SegmentationService(yolo=yolo, grounded_sam2=grounded_sam2)

    application.state.storage = storage
    application.state.image_validator = ImageUploadValidator(
        max_bytes=settings.max_upload_bytes,
        max_pixels=settings.max_image_pixels,
    )
    application.state.image_to_3d_pipeline = ImageTo3DPipeline(
        triposr=LocalTripoSRProvider(runner=runner, storage=storage),
        stable_fast_3d=LocalStableFast3DProvider(runner=runner, storage=storage),
        segmentation=segmentation,
        storage=storage,
        gpu_limiter=gpu_limiter,
    )
    application.state.remove_background_pipeline = RemoveBackgroundPipeline(
        segmentation=segmentation,
        storage=storage,
        gpu_limiter=gpu_limiter,
    )
    yield


def create_app() -> FastAPI:
    application = FastAPI(
        title="Image to 3D API",
        version="0.1.0",
        lifespan=lifespan,
    )

    @application.middleware("http")
    async def log_request(request: Request, call_next):
        supplied_id = request.headers.get("x-request-id", "")
        request_id = (
            supplied_id if REQUEST_ID_PATTERN.fullmatch(supplied_id) else uuid4().hex
        )
        started = perf_counter()
        try:
            response = await call_next(request)
        except Exception:
            logger.exception(
                "Request failed request_id=%s method=%s path=%s",
                request_id,
                request.method,
                request.url.path,
            )
            raise
        elapsed_ms = (perf_counter() - started) * 1000
        response.headers["X-Request-ID"] = request_id
        logger.info(
            "Request completed request_id=%s method=%s path=%s status=%s elapsed_ms=%.1f",
            request_id,
            request.method,
            request.url.path,
            response.status_code,
            elapsed_ms,
        )
        return response

    application.include_router(router)
    return application


app = create_app()
