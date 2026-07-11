from pathlib import Path
from typing import Final
import os


BASE_DIR: Final = Path(__file__).resolve().parent.parent
OUTPUT_DIR: Final = BASE_DIR / "storage" / "outputs"
TEMP_DIR: Final = BASE_DIR / "storage" / "tmp"
PROCESSED_DIR: Final = BASE_DIR / "storage" / "processed"
LOCAL_MODEL_DIR: Final = BASE_DIR / "models"
IS_WINDOWS: Final = os.name == "nt"
DEFAULT_TRIPOSR_REPO: Final = (
    LOCAL_MODEL_DIR / "TripoSR" if IS_WINDOWS else BASE_DIR / "vendor" / "TripoSR"
)
DEFAULT_TRIPOSR_MODEL: Final = (
    LOCAL_MODEL_DIR / "hf" / "TripoSR" if IS_WINDOWS else BASE_DIR / "vendor" / "weights" / "TripoSR"
)
DEFAULT_TRIPOSR_PYTHON: Final = (
    BASE_DIR / ".venv-triposr" / "Scripts" / "python.exe"
    if IS_WINDOWS
    else BASE_DIR / ".venv" / "bin" / "python"
)
DEFAULT_YOLO_MODEL: Final = (
    BASE_DIR / "yolo11s-seg.pt"
    if IS_WINDOWS
    else BASE_DIR / "vendor" / "weights" / "yolo" / "yolo11s-seg.pt"
)


class Settings:
    image_to_3d_provider: str = os.getenv("IMAGE_TO_3D_PROVIDER", "local_triposr")
    local_triposr_repo_dir: Path = Path(
        os.getenv("LOCAL_TRIPOSR_REPO_DIR", str(DEFAULT_TRIPOSR_REPO))
    )
    local_triposr_python: Path = Path(
        os.getenv("LOCAL_TRIPOSR_PYTHON", str(DEFAULT_TRIPOSR_PYTHON))
    )
    local_triposr_model_path: str = os.getenv(
        "LOCAL_TRIPOSR_MODEL_PATH",
        str(DEFAULT_TRIPOSR_MODEL),
    )
    local_triposr_device: str = os.getenv(
        "LOCAL_TRIPOSR_DEVICE", "cpu" if IS_WINDOWS else "cuda:0"
    )
    local_triposr_timeout_seconds: int = int(os.getenv("LOCAL_TRIPOSR_TIMEOUT_SECONDS", "600"))
    yolo_segmentation_model: str = os.getenv("YOLO_SEGMENTATION_MODEL", str(DEFAULT_YOLO_MODEL))
    yolo_segmentation_device: str = os.getenv("YOLO_SEGMENTATION_DEVICE", "auto")
    yolo_segmentation_confidence: float = float(os.getenv("YOLO_SEGMENTATION_CONFIDENCE", "0.25"))
    max_upload_bytes: int = int(os.getenv("MAX_UPLOAD_BYTES", str(10 * 1024 * 1024)))


settings = Settings()
