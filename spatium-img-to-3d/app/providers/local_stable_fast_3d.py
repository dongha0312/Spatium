import asyncio
import os
import shutil
from io import BytesIO
from pathlib import Path
from tempfile import NamedTemporaryFile

from fastapi import HTTPException
from PIL import Image

from app.config import BASE_DIR, OUTPUT_DIR, TEMP_DIR, settings


REMBG_STUB_DIR = BASE_DIR / "scripts" / "sf3d_no_rembg"


class LocalStableFast3DProvider:
    """Run Stability AI's open-weight Stable Fast 3D model locally."""

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

        TEMP_DIR.mkdir(parents=True, exist_ok=True)
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        suffix = Path(filename).suffix.lower()
        if suffix not in {".png", ".jpg", ".jpeg", ".webp"}:
            suffix = ".png"

        with NamedTemporaryFile(dir=TEMP_DIR, suffix=suffix, delete=False) as image_file:
            image_file.write(image_bytes)
            image_path = Path(image_file.name)

        run_output_dir = OUTPUT_DIR / f"local-sf3d-{image_path.stem}"
        run_output_dir.mkdir(parents=True, exist_ok=True)
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
            process = await asyncio.create_subprocess_exec(
                *args,
                cwd=settings.local_sf3d_repo_dir,
                env=process_env,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            try:
                stdout, stderr = await asyncio.wait_for(
                    process.communicate(),
                    timeout=settings.local_sf3d_timeout_seconds,
                )
            except asyncio.TimeoutError as exc:
                process.kill()
                await process.communicate()
                raise HTTPException(
                    status_code=504,
                    detail="Local Stable Fast 3D timed out.",
                ) from exc

            if process.returncode != 0:
                raise HTTPException(
                    status_code=502,
                    detail={
                        "provider": "local_stable_fast_3d",
                        "message": "Local Stable Fast 3D failed.",
                        "stdout": stdout.decode(errors="replace")[-4000:],
                        "stderr": stderr.decode(errors="replace")[-4000:],
                    },
                )

            matches = sorted(run_output_dir.rglob("*.glb"))
            if not matches:
                raise HTTPException(
                    status_code=502,
                    detail="Stable Fast 3D finished but no GLB file was created.",
                )
            return matches[-1].read_bytes()
        finally:
            shutil.rmtree(run_output_dir, ignore_errors=True)
            image_path.unlink(missing_ok=True)

    @staticmethod
    def _validate_transparent_input(image_bytes: bytes) -> None:
        try:
            image = Image.open(BytesIO(image_bytes)).convert("RGBA")
        except Exception as exc:
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
        missing = [str(path) for path in required if not path.exists()]
        if missing:
            raise HTTPException(
                status_code=503,
                detail={
                    "provider": "local_stable_fast_3d",
                    "message": (
                        "Local Stable Fast 3D is not installed. "
                        "Run scripts/setup_local_sf3d.sh first."
                    ),
                    "missing": missing,
                },
            )
