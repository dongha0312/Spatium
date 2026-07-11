import asyncio
import shutil
from io import BytesIO
from pathlib import Path
from tempfile import NamedTemporaryFile

from fastapi import HTTPException
from PIL import Image

from app.config import OUTPUT_DIR, TEMP_DIR, settings


class LocalTripoSRProvider:
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
        TEMP_DIR.mkdir(parents=True, exist_ok=True)
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

        image_bytes, suffix = self._prepare_triposr_input(
            image_bytes,
            filename,
            remove_background,
            foreground_ratio,
        )
        with NamedTemporaryFile(dir=TEMP_DIR, suffix=suffix, delete=False) as image_file:
            image_file.write(image_bytes)
            image_path = Path(image_file.name)

        run_output_dir = OUTPUT_DIR / f"local-triposr-{image_path.stem}"
        run_output_dir.mkdir(parents=True, exist_ok=True)
        # TripoSR only creates this directory when it runs its own background
        # removal. Pre-segmented PNG input must create it ahead of time.
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

        process = await asyncio.create_subprocess_exec(
            *args,
            cwd=settings.local_triposr_repo_dir,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

        try:
            stdout, stderr = await asyncio.wait_for(
                process.communicate(),
                timeout=settings.local_triposr_timeout_seconds,
            )
        except asyncio.TimeoutError as exc:
            process.kill()
            raise HTTPException(
                status_code=504,
                detail="Local TripoSR timed out. Lower mesh resolution or check GPU availability.",
            ) from exc

        if process.returncode != 0:
            raise HTTPException(
                status_code=502,
                detail={
                    "provider": "local_triposr",
                    "message": "Local TripoSR failed.",
                    "stdout": stdout.decode(errors="replace")[-4000:],
                    "stderr": stderr.decode(errors="replace")[-4000:],
                },
            )

        glb_path = run_output_dir / "0" / "mesh.glb"
        if not glb_path.exists():
            matches = sorted(run_output_dir.rglob("*.glb"))
            if not matches:
                raise HTTPException(
                    status_code=502,
                    detail="Local TripoSR finished but no GLB file was created.",
                )
            glb_path = matches[-1]

        final_bytes = glb_path.read_bytes()
        shutil.rmtree(run_output_dir, ignore_errors=True)
        image_path.unlink(missing_ok=True)
        return final_bytes

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
            image = Image.open(BytesIO(image_bytes)).convert("RGBA")
        except Exception:
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

    def _validate_installation(self) -> None:
        missing = []
        if not settings.local_triposr_python.exists():
            missing.append(str(settings.local_triposr_python))
        if not settings.local_triposr_repo_dir.exists():
            missing.append(str(settings.local_triposr_repo_dir))
        if not (settings.local_triposr_repo_dir / "run.py").exists():
            missing.append(str(settings.local_triposr_repo_dir / "run.py"))

        if missing:
            raise HTTPException(
                status_code=500,
                detail={
                    "provider": "local_triposr",
                    "message": "Local TripoSR is not installed or its WSL environment is unavailable.",
                    "missing": missing,
                },
            )
