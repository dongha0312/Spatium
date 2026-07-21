import logging
import os
from io import BytesIO
from pathlib import Path

from fastapi import HTTPException
from PIL import Image

from app.config import BASE_DIR, settings
from app.services.process_runner import (
    AsyncProcessRunner,
    ProcessStartError,
    ProcessTimeoutError,
)
from app.services.storage import StorageService


REMBG_STUB_DIR = BASE_DIR / "scripts" / "sf3d_no_rembg"
logger = logging.getLogger(__name__)


class LocalStableFast3DProvider:
    """Run Stability AI's open-weight Stable Fast 3D model locally."""

    def __init__(
        self,
        *,
        runner: AsyncProcessRunner | None = None,
        storage: StorageService | None = None,
    ) -> None:
        self.runner = runner or AsyncProcessRunner()
        self.storage = storage or StorageService()

    async def generate(
        self,
        *,
        image_bytes: bytes,
        filename: str,
        texture_resolution: int,
        remesh: str,
        foreground_ratio: float,
    ) -> bytes:
        self._validate_installation()
        self._validate_transparent_input(image_bytes)
        if texture_resolution not in {512, 1024, 2048}:
            raise HTTPException(
                status_code=422,
                detail="texture_resolution must be 512, 1024, or 2048.",
            )
        if remesh not in {"none", "triangle", "quad"}:
            raise HTTPException(
                status_code=422,
                detail="remesh must be none, triangle, or quad.",
            )

        suffix = Path(filename).suffix.lower()
        if suffix not in {".png", ".jpg", ".jpeg", ".webp"}:
            suffix = ".png"

        with self.storage.temporary_file(suffix=suffix) as image_path:
            image_path.write_bytes(image_bytes)
            with self.storage.temporary_directory(prefix="local-sf3d-") as run_output_dir:
                args = [
                    str(settings.local_sf3d_python),
                    "run.py",
                    str(image_path),
                    "--device",
                    settings.local_sf3d_device,
                    "--pretrained-model",
                    settings.local_sf3d_model_path,
                    "--foreground-ratio",
                    str(foreground_ratio),
                    "--texture-resolution",
                    str(texture_resolution),
                    "--remesh_option",
                    remesh,
                    "--output-dir",
                    str(run_output_dir),
                ]
                process_env = os.environ.copy()
                existing_pythonpath = process_env.get("PYTHONPATH", "")
                process_env["PYTHONPATH"] = os.pathsep.join(
                    value for value in (str(REMBG_STUB_DIR), existing_pythonpath) if value
                )

                try:
                    result = await self.runner.run(
                        args,
                        cwd=settings.local_sf3d_repo_dir,
                        env=process_env,
                        timeout_seconds=settings.local_sf3d_timeout_seconds,
                    )
                except ProcessTimeoutError as exc:
                    raise HTTPException(
                        status_code=504,
                        detail="Local Stable Fast 3D timed out.",
                    ) from exc
                except ProcessStartError as exc:
                    logger.exception("Could not start Local Stable Fast 3D")
                    raise HTTPException(
                        status_code=502,
                        detail="Local Stable Fast 3D could not be started.",
                    ) from exc

                if result.returncode != 0:
                    logger.error(
                        "Local Stable Fast 3D failed with exit code %s; stdout=%s stderr=%s",
                        result.returncode,
                        self._tail(result.stdout),
                        self._tail(result.stderr),
                    )
                    raise HTTPException(
                        status_code=502,
                        detail="Local Stable Fast 3D failed.",
                    )

                matches = sorted(run_output_dir.rglob("*.glb"))
                if not matches:
                    raise HTTPException(
                        status_code=502,
                        detail="Stable Fast 3D finished but no GLB file was created.",
                    )
                return matches[-1].read_bytes()

    @staticmethod
    def _tail(value: bytes, limit: int = 4000) -> str:
        return value.decode(errors="replace")[-limit:]

    @staticmethod
    def _validate_transparent_input(image_bytes: bytes) -> None:
        try:
            with Image.open(BytesIO(image_bytes)) as opened:
                image = opened.convert("RGBA")
        except (OSError, ValueError) as exc:
            raise HTTPException(
                status_code=422,
                detail="Stable Fast 3D input is not a readable image.",
            ) from exc

        alpha = image.getchannel("A")
        if alpha.getbbox() is None:
            raise HTTPException(
                status_code=422,
                detail="Stable Fast 3D input has an empty foreground mask.",
            )
        if alpha.getextrema()[0] == 255:
            raise HTTPException(
                status_code=422,
                detail=(
                    "Local Stable Fast 3D requires the transparent PNG created "
                    "by YOLO background removal."
                ),
            )

    @staticmethod
    def _validate_installation() -> None:
        required = [
            settings.local_sf3d_python,
            settings.local_sf3d_repo_dir,
            settings.local_sf3d_repo_dir / "run.py",
            REMBG_STUB_DIR / "rembg" / "__init__.py",
            Path(settings.local_sf3d_model_path) / "model.safetensors",
            Path(settings.local_sf3d_model_path) / "config.yaml",
        ]
        missing = [path for path in required if not path.exists()]
        if missing:
            logger.error("Local Stable Fast 3D installation is incomplete: %s", missing)
            raise HTTPException(
                status_code=503,
                detail=(
                    "Local Stable Fast 3D is not installed. "
                    "Run scripts/setup_local_sf3d.sh first."
                ),
            )
