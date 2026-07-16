import logging
from io import BytesIO
from pathlib import Path

from fastapi import HTTPException
from PIL import Image

from app.config import settings
from app.services.process_runner import (
    AsyncProcessRunner,
    ProcessStartError,
    ProcessTimeoutError,
)
from app.services.storage import StorageService


logger = logging.getLogger(__name__)


class LocalTripoSRProvider:
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
        content_type: str,
        mc_resolution: int,
        remove_background: bool,
        foreground_ratio: float,
    ) -> bytes:
        self._validate_installation()
        image_bytes, suffix = self._prepare_triposr_input(
            image_bytes,
            filename,
            remove_background,
            foreground_ratio,
        )

        with self.storage.temporary_file(suffix=suffix) as image_path:
            image_path.write_bytes(image_bytes)
            with self.storage.temporary_directory(prefix="local-triposr-") as run_output_dir:
                (run_output_dir / "0").mkdir(exist_ok=True)
                args = [
                    str(settings.local_triposr_python),
                    "run.py",
                    str(image_path),
                    "--device",
                    settings.local_triposr_device,
                    "--pretrained-model-name-or-path",
                    settings.local_triposr_model_path,
                    "--mc-resolution",
                    str(mc_resolution),
                    "--output-dir",
                    str(run_output_dir),
                    "--model-save-format",
                    "glb",
                ]
                if not remove_background:
                    args.append("--no-remove-bg")
                else:
                    args.extend(["--foreground-ratio", str(foreground_ratio)])

                try:
                    result = await self.runner.run(
                        args,
                        cwd=settings.local_triposr_repo_dir,
                        timeout_seconds=settings.local_triposr_timeout_seconds,
                    )
                except ProcessTimeoutError as exc:
                    raise HTTPException(
                        status_code=504,
                        detail=(
                            "Local TripoSR timed out. Lower mesh resolution or "
                            "check GPU availability."
                        ),
                    ) from exc
                except ProcessStartError as exc:
                    logger.exception("Could not start Local TripoSR")
                    raise HTTPException(
                        status_code=502,
                        detail="Local TripoSR could not be started.",
                    ) from exc

                if result.returncode != 0:
                    logger.error(
                        "Local TripoSR failed with exit code %s; stdout=%s stderr=%s",
                        result.returncode,
                        self._tail(result.stdout),
                        self._tail(result.stderr),
                    )
                    raise HTTPException(
                        status_code=502,
                        detail="Local TripoSR failed.",
                    )

                glb_path = run_output_dir / "0" / "mesh.glb"
                if not glb_path.is_file():
                    matches = sorted(run_output_dir.rglob("*.glb"))
                    if not matches:
                        raise HTTPException(
                            status_code=502,
                            detail="Local TripoSR finished but no GLB file was created.",
                        )
                    glb_path = matches[-1]
                return glb_path.read_bytes()

    @staticmethod
    def _tail(value: bytes, limit: int = 4000) -> str:
        return value.decode(errors="replace")[-limit:]

    @staticmethod
    def _prepare_triposr_input(
        image_bytes: bytes,
        filename: str,
        remove_background: bool,
        foreground_ratio: float,
    ) -> tuple[bytes, str]:
        """Flatten a prepared RGBA object onto TripoSR's expected gray canvas."""
        if remove_background:
            return image_bytes, Path(filename).suffix or ".png"

        try:
            with Image.open(BytesIO(image_bytes)) as opened:
                image = opened.convert("RGBA")
        except (OSError, ValueError):
            return image_bytes, Path(filename).suffix or ".png"

        alpha = image.getchannel("A")
        bounds = alpha.getbbox()
        if bounds is None or alpha.getextrema() == (255, 255):
            return image_bytes, Path(filename).suffix or ".png"

        foreground = image.crop(bounds)
        ratio = min(max(foreground_ratio, 0.5), 0.95)
        side = max(64, round(max(foreground.width, foreground.height) / ratio))
        canvas = Image.new("RGB", (side, side), (128, 128, 128))
        offset = ((side - foreground.width) // 2, (side - foreground.height) // 2)
        canvas.paste(foreground.convert("RGB"), offset, foreground.getchannel("A"))

        output = BytesIO()
        canvas.save(output, format="PNG")
        return output.getvalue(), ".png"

    @staticmethod
    def _validate_installation() -> None:
        required = [
            settings.local_triposr_python,
            settings.local_triposr_repo_dir,
            settings.local_triposr_repo_dir / "run.py",
        ]
        missing = [path for path in required if not path.exists()]
        if missing:
            logger.error("Local TripoSR installation is incomplete: %s", missing)
            raise HTTPException(
                status_code=503,
                detail="Local TripoSR is not installed or is unavailable.",
            )
