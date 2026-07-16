from __future__ import annotations

import json
import logging
import os
from dataclasses import dataclass
from pathlib import Path

from fastapi import HTTPException

from app.config import BASE_DIR, settings
from app.services.process_runner import (
    AsyncProcessRunner,
    ProcessStartError,
    ProcessTimeoutError,
)
from app.services.storage import StorageService


logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class GroundedSegmentationResult:
    image_bytes: bytes
    detected_label: str
    translated_query: str
    device: str
    confidence: float


class GroundedSam2Service:
    def __init__(
        self,
        *,
        runner: AsyncProcessRunner | None = None,
        storage: StorageService | None = None,
    ) -> None:
        self.runner = runner or AsyncProcessRunner()
        self.storage = storage or StorageService()

    async def remove_background(
        self, image_bytes: bytes, object_query: str
    ) -> GroundedSegmentationResult:
        query = object_query.strip()
        if not query:
            raise HTTPException(
                status_code=422,
                detail="object_query is required for grounded_sam2.",
            )

        python = settings.grounded_sam2_python
        runner_path = BASE_DIR / "scripts" / "run_grounded_sam2.py"
        required = {
            "segmentation Python": python,
            "runner": runner_path,
            "GroundingDINO model": settings.grounding_dino_model,
            "SAM2 model": settings.sam2_model,
            "translation model": settings.translation_model,
        }
        missing = [f"{name}: {path}" for name, path in required.items() if not Path(path).exists()]
        if missing:
            logger.error("Grounded SAM2 installation is incomplete: %s", missing)
            raise HTTPException(
                status_code=503,
                detail=(
                    "GroundingDINO+SAM2 is not installed. "
                    "Run scripts/setup_grounded_sam2.sh."
                ),
            )

        with self.storage.temporary_directory(prefix="grounded-sam2-") as temp:
            input_path = temp / "input.png"
            output_path = temp / "segmented.png"
            metadata_path = temp / "metadata.json"
            input_path.write_bytes(image_bytes)
            command = [
                str(python),
                str(runner_path),
                "--image",
                str(input_path),
                "--query",
                query,
                "--output",
                str(output_path),
                "--metadata",
                str(metadata_path),
                "--translation-model",
                str(settings.translation_model),
                "--grounding-dino-model",
                str(settings.grounding_dino_model),
                "--sam2-model",
                str(settings.sam2_model),
                "--device",
                settings.grounded_sam2_device,
                "--box-threshold",
                str(settings.grounding_dino_box_threshold),
                "--text-threshold",
                str(settings.grounding_dino_text_threshold),
            ]
            env = os.environ.copy()
            env["HF_HUB_OFFLINE"] = "1"
            env["TRANSFORMERS_OFFLINE"] = "1"
            try:
                result = await self.runner.run(
                    command,
                    env=env,
                    timeout_seconds=settings.grounded_sam2_timeout_seconds,
                )
            except ProcessTimeoutError as exc:
                raise HTTPException(
                    status_code=504,
                    detail="GroundingDINO+SAM2 timed out.",
                ) from exc
            except ProcessStartError as exc:
                logger.exception("Could not start GroundingDINO+SAM2")
                raise HTTPException(
                    status_code=502,
                    detail="GroundingDINO+SAM2 could not be started.",
                ) from exc

            if result.returncode != 0 or not output_path.is_file() or not metadata_path.is_file():
                logger.error(
                    "GroundingDINO+SAM2 failed with exit code %s; stdout=%s stderr=%s",
                    result.returncode,
                    self._tail(result.stdout, 4000),
                    self._tail(result.stderr, 8000),
                )
                raise HTTPException(
                    status_code=502,
                    detail="GroundingDINO+SAM2 failed.",
                )

            try:
                metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
                return GroundedSegmentationResult(
                    image_bytes=output_path.read_bytes(),
                    detected_label=str(metadata["detected_label"]),
                    translated_query=str(metadata["translated_query"]),
                    device=str(metadata["device"]),
                    confidence=float(metadata["confidence"]),
                )
            except (OSError, ValueError, KeyError, TypeError) as exc:
                logger.exception("GroundingDINO+SAM2 produced invalid output metadata")
                raise HTTPException(
                    status_code=502,
                    detail="GroundingDINO+SAM2 produced an invalid result.",
                ) from exc

    @staticmethod
    def _tail(value: bytes, limit: int) -> str:
        return value.decode("utf-8", errors="replace").strip()[-limit:]
