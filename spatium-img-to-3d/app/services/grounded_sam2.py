from __future__ import annotations

import asyncio
import json
import os
import tempfile
from dataclasses import dataclass
from pathlib import Path

from fastapi import HTTPException

from app.config import BASE_DIR, settings


@dataclass(frozen=True)
class GroundedSegmentationResult:
    image_bytes: bytes
    detected_label: str
    translated_query: str
    device: str
    confidence: float


class GroundedSam2Service:
    async def remove_background(
        self, image_bytes: bytes, object_query: str
    ) -> GroundedSegmentationResult:
        query = object_query.strip()
        if not query:
            raise HTTPException(status_code=422, detail="object_query is required for grounded_sam2.")

        python = settings.grounded_sam2_python
        runner = BASE_DIR / "scripts" / "run_grounded_sam2.py"
        required = {
            "segmentation Python": python,
            "runner": runner,
            "GroundingDINO model": settings.grounding_dino_model,
            "SAM2 model": settings.sam2_model,
            "translation model": settings.translation_model,
        }
        missing = [f"{name}: {path}" for name, path in required.items() if not Path(path).exists()]
        if missing:
            raise HTTPException(
                status_code=503,
                detail="GroundingDINO+SAM2 is not installed. Run scripts/setup_grounded_sam2.sh. Missing: "
                + "; ".join(missing),
            )

        with tempfile.TemporaryDirectory(prefix="grounded-sam2-") as temp_dir:
            temp = Path(temp_dir)
            input_path = temp / "input.png"
            output_path = temp / "segmented.png"
            metadata_path = temp / "metadata.json"
            input_path.write_bytes(image_bytes)
            command = [
                str(python), str(runner),
                "--image", str(input_path),
                "--query", query,
                "--output", str(output_path),
                "--metadata", str(metadata_path),
                "--translation-model", str(settings.translation_model),
                "--grounding-dino-model", str(settings.grounding_dino_model),
                "--sam2-model", str(settings.sam2_model),
                "--device", settings.grounded_sam2_device,
                "--box-threshold", str(settings.grounding_dino_box_threshold),
                "--text-threshold", str(settings.grounding_dino_text_threshold),
            ]
            env = os.environ.copy()
            env["HF_HUB_OFFLINE"] = "1"
            env["TRANSFORMERS_OFFLINE"] = "1"
            process = await asyncio.create_subprocess_exec(
                *command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=env,
            )
            try:
                stdout, stderr = await asyncio.wait_for(
                    process.communicate(), timeout=settings.grounded_sam2_timeout_seconds
                )
            except TimeoutError:
                process.kill()
                await process.communicate()
                raise HTTPException(status_code=504, detail="GroundingDINO+SAM2 timed out.")

            if process.returncode != 0 or not output_path.exists() or not metadata_path.exists():
                detail = stderr.decode("utf-8", errors="replace").strip()
                stdout_text = stdout.decode("utf-8", errors="replace").strip()
                raise HTTPException(
                    status_code=500,
                    detail={
                        "provider": "grounded_sam2",
                        "message": "GroundingDINO+SAM2 failed.",
                        "stdout": stdout_text[-4000:],
                        "stderr": detail[-8000:],
                    },
                )

            metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
            return GroundedSegmentationResult(
                image_bytes=output_path.read_bytes(),
                detected_label=str(metadata["detected_label"]),
                translated_query=str(metadata["translated_query"]),
                device=str(metadata["device"]),
                confidence=float(metadata["confidence"]),
            )
