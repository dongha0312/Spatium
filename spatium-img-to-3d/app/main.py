from uuid import uuid4

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse, HTMLResponse

from app.config import OUTPUT_DIR, PROCESSED_DIR, settings
from app.providers.local_triposr import LocalTripoSRProvider
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
        }
    ]


@app.post("/v1/image-to-3d")
async def image_to_3d(
    image: UploadFile = File(...),
    foreground_ratio: float | None = Form(None),
    mc_resolution: int = Form(256),
    remove_background: bool = Form(True),
    background_removal: str = Form("yolo"),
    target_class: str | None = Form(None),
) -> dict[str, str]:
    validate_image(image)
    image_bytes = await image.read()

    if len(image_bytes) > settings.max_upload_bytes:
        raise HTTPException(status_code=413, detail="Image is larger than MAX_UPLOAD_BYTES.")

    filename = image.filename or "image.png"
    content_type = image.content_type or "application/octet-stream"
    segmented_object: str | None = None
    if remove_background and background_removal.lower() == "yolo":
        segmented = await YoloSegmentationService().remove_background(image_bytes, target_class)
        image_bytes = segmented.image_bytes
        filename = "segmented.png"
        content_type = "image/png"
        segmented_object = segmented.detected_label
        # The local TripoSR runner must use this prepared alpha image as-is.
        # Running its rembg stage again would duplicate work and may download
        # another background-removal model at request time.
        remove_background = False

    provider_name = "local_triposr"
    provider = LocalTripoSRProvider()
    output_bytes = await provider.generate(
        image_bytes=image_bytes,
        filename=filename,
        content_type=content_type,
        mc_resolution=mc_resolution,
        remove_background=remove_background,
        foreground_ratio=foreground_ratio or 0.85,
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
    return response


@app.post("/v1/remove-background")
async def remove_background(
    image: UploadFile = File(...),
    target_class: str | None = Form(None),
) -> dict[str, str]:
    validate_image(image)
    image_bytes = await image.read()
    if len(image_bytes) > settings.max_upload_bytes:
        raise HTTPException(status_code=413, detail="Image is larger than MAX_UPLOAD_BYTES.")

    result = await YoloSegmentationService().remove_background(image_bytes, target_class)
    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    image_id = uuid4().hex
    output_path = PROCESSED_DIR / f"{image_id}.png"
    output_path.write_bytes(result.image_bytes)
    return {
        "id": image_id,
        "format": "png",
        "segmented_object": result.detected_label,
        "device": result.device,
        "download_url": f"/v1/images/{output_path.name}",
    }


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
