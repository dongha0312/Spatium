from uuid import uuid4

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse, HTMLResponse

from app.config import OUTPUT_DIR, PROCESSED_DIR, settings
from app.providers.local_triposr import LocalTripoSRProvider
from app.providers.local_stable_fast_3d import LocalStableFast3DProvider
from app.services.grounded_sam2 import GroundedSam2Service
from app.services.yolo_segmentation import YoloSegmentationService
from app.ui import INDEX_HTML


app = FastAPI(title="Image to 3D API", version="0.1.0")


@app.get("/", response_class=HTMLResponse)
async def index() -> str:
    return INDEX_HTML


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/v1/providers")
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


@app.get("/v1/segmentation-providers")
async def segmentation_providers() -> list[dict[str, str]]:
    return [
        {"id": "yolo", "name": "YOLO segmentation", "query": "class"},
        {
            "id": "grounded_sam2",
            "name": "GroundingDINO + SAM2",
            "query": "natural_language",
        },
    ]


@app.post("/v1/image-to-3d")
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
) -> dict[str, str]:
    validate_image(image)
    image_bytes = await image.read()

    if len(image_bytes) > settings.max_upload_bytes:
        raise HTTPException(status_code=413, detail="Image is larger than MAX_UPLOAD_BYTES.")

    filename = image.filename or "image.png"
    content_type = image.content_type or "application/octet-stream"
    segmented_object: str | None = None
    translated_query: str | None = None
    segmentation_name: str | None = None
    if remove_background:
        selected_segmentation = (segmentation_provider or background_removal).strip().lower()
        if selected_segmentation == "none":
            selected_segmentation = ""
        segmentation_name = selected_segmentation or None
    if remove_background and segmentation_name:
        segmented = await segment_image(
            image_bytes=image_bytes,
            segmentation_provider=segmentation_name,
            target_class=target_class,
            object_query=object_query,
        )
        image_bytes = segmented.image_bytes
        filename = "segmented.png"
        content_type = "image/png"
        segmented_object = segmented.detected_label
        translated_query = getattr(segmented, "translated_query", None)
        # The local TripoSR runner must use this prepared alpha image as-is.
        # Running its rembg stage again would duplicate work and may download
        # another background-removal model at request time.
        remove_background = False

    provider_name = provider.strip().lower()
    if provider_name == "local_triposr":
        output_bytes = await LocalTripoSRProvider().generate(
            image_bytes=image_bytes,
            filename=filename,
            content_type=content_type,
            mc_resolution=mc_resolution,
            remove_background=remove_background,
            foreground_ratio=foreground_ratio or 0.85,
        )
    elif provider_name == "local_stable_fast_3d":
        output_bytes = await LocalStableFast3DProvider().generate(
            image_bytes=image_bytes,
            filename=filename,
            texture_resolution=texture_resolution,
            remesh=remesh.strip().lower(),
            foreground_ratio=foreground_ratio or 0.85,
        )
    else:
        raise HTTPException(
            status_code=422,
            detail=(
                "provider must be 'local_triposr' or "
                "'local_stable_fast_3d'."
            ),
        )

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    asset_id = uuid4().hex
    output_path = OUTPUT_DIR / f"{asset_id}.glb"
    output_path.write_bytes(output_bytes)

    response = {
        "id": asset_id,
        "provider": provider_name,
        "format": "glb",
        "download_url": f"/v1/assets/{output_path.name}",
    }
    if segmented_object:
        response["segmented_object"] = segmented_object
    if segmentation_name:
        response["segmentation_provider"] = segmentation_name
    if translated_query:
        response["translated_query"] = translated_query
    return response


@app.post("/v1/remove-background")
async def remove_background(
    image: UploadFile = File(...),
    segmentation_provider: str = Form("yolo"),
    target_class: str | None = Form(None),
    object_query: str | None = Form(None),
) -> dict[str, str]:
    validate_image(image)
    image_bytes = await image.read()
    if len(image_bytes) > settings.max_upload_bytes:
        raise HTTPException(status_code=413, detail="Image is larger than MAX_UPLOAD_BYTES.")

    provider_name = segmentation_provider.strip().lower()
    result = await segment_image(
        image_bytes=image_bytes,
        segmentation_provider=provider_name,
        target_class=target_class,
        object_query=object_query,
    )
    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    image_id = uuid4().hex
    output_path = PROCESSED_DIR / f"{image_id}.png"
    output_path.write_bytes(result.image_bytes)
    response = {
        "id": image_id,
        "format": "png",
        "segmentation_provider": provider_name,
        "segmented_object": result.detected_label,
        "device": result.device,
        "download_url": f"/v1/images/{output_path.name}",
    }
    translated_query = getattr(result, "translated_query", None)
    confidence = getattr(result, "confidence", None)
    if translated_query:
        response["translated_query"] = translated_query
    if confidence is not None:
        response["confidence"] = str(round(float(confidence), 4))
    return response


@app.get("/v1/assets/{filename}")
async def download_asset(filename: str) -> FileResponse:
    if not filename.endswith(".glb") or "/" in filename or "\\" in filename:
        raise HTTPException(status_code=400, detail="Invalid asset filename.")

    path = OUTPUT_DIR / filename
    if not path.exists():
        raise HTTPException(status_code=404, detail="Asset not found.")

    return FileResponse(
        path,
        media_type="model/gltf-binary",
        filename=filename,
    )


@app.get("/v1/images/{filename}")
async def download_processed_image(filename: str) -> FileResponse:
    if not filename.endswith(".png") or "/" in filename or "\\" in filename:
        raise HTTPException(status_code=400, detail="Invalid image filename.")

    path = PROCESSED_DIR / filename
    if not path.exists():
        raise HTTPException(status_code=404, detail="Image not found.")

    return FileResponse(path, media_type="image/png", filename=filename)


def validate_image(image: UploadFile) -> None:
    allowed_types = {"image/png", "image/jpeg", "image/webp"}
    if image.content_type not in allowed_types:
        raise HTTPException(
            status_code=415,
            detail="Unsupported image type. Use PNG, JPEG, or WebP.",
        )


async def segment_image(
    image_bytes: bytes,
    segmentation_provider: str,
    target_class: str | None,
    object_query: str | None,
):
    if segmentation_provider == "yolo":
        return await YoloSegmentationService().remove_background(image_bytes, target_class)
    if segmentation_provider == "grounded_sam2":
        return await GroundedSam2Service().remove_background(image_bytes, object_query or "")
    raise HTTPException(
        status_code=422,
        detail="segmentation_provider must be 'yolo' or 'grounded_sam2'.",
    )
