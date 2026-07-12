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
DEFAULT_SF3D_REPO: Final = BASE_DIR / "vendor" / "stable-fast-3d"
DEFAULT_SF3D_MODEL: Final = BASE_DIR / "vendor" / "weights" / "stable-fast-3d"
DEFAULT_SF3D_PYTHON: Final = BASE_DIR / ".venv-sf3d" / "bin" / "python"
DEFAULT_SEGMENTATION_PYTHON: Final = (
    BASE_DIR / ".venv-segmentation" / "Scripts" / "python.exe"
    if IS_WINDOWS
    else BASE_DIR / ".venv-segmentation" / "bin" / "python"
)
DEFAULT_GROUNDING_DINO_MODEL: Final = (
    BASE_DIR / "vendor" / "weights" / "grounding-dino-tiny"
)
DEFAULT_SAM2_MODEL: Final = BASE_DIR / "vendor" / "weights" / "sam2.1-hiera-small"
DEFAULT_TRANSLATION_MODEL: Final = BASE_DIR / "vendor" / "weights" / "opus-mt-ko-en"


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
    local_sf3d_repo_dir: Path = Path(
        os.getenv("LOCAL_SF3D_REPO_DIR", str(DEFAULT_SF3D_REPO))
    )
    local_sf3d_python: Path = Path(
        os.getenv("LOCAL_SF3D_PYTHON", str(DEFAULT_SF3D_PYTHON))
    )
    local_sf3d_model_path: str = os.getenv(
        "LOCAL_SF3D_MODEL_PATH", str(DEFAULT_SF3D_MODEL)
    )
    local_sf3d_device: str = os.getenv("LOCAL_SF3D_DEVICE", "cuda")
    local_sf3d_timeout_seconds: int = int(
        os.getenv("LOCAL_SF3D_TIMEOUT_SECONDS", "600")
    )
    yolo_segmentation_model: str = os.getenv("YOLO_SEGMENTATION_MODEL", str(DEFAULT_YOLO_MODEL))
    yolo_segmentation_device: str = os.getenv("YOLO_SEGMENTATION_DEVICE", "auto")
    yolo_segmentation_confidence: float = float(os.getenv("YOLO_SEGMENTATION_CONFIDENCE", "0.25"))
    grounded_sam2_python: Path = Path(
        os.getenv("GROUNDED_SAM2_PYTHON", str(DEFAULT_SEGMENTATION_PYTHON))
    )
    grounding_dino_model: Path = Path(
        os.getenv("GROUNDING_DINO_MODEL", str(DEFAULT_GROUNDING_DINO_MODEL))
    )
    sam2_model: Path = Path(os.getenv("SAM2_MODEL", str(DEFAULT_SAM2_MODEL)))
    translation_model: Path = Path(
        os.getenv("KO_EN_TRANSLATION_MODEL", str(DEFAULT_TRANSLATION_MODEL))
    )
    grounded_sam2_device: str = os.getenv("GROUNDED_SAM2_DEVICE", "cuda")
    grounding_dino_box_threshold: float = float(
        os.getenv("GROUNDING_DINO_BOX_THRESHOLD", "0.30")
    )
    grounding_dino_text_threshold: float = float(
        os.getenv("GROUNDING_DINO_TEXT_THRESHOLD", "0.25")
    )
    grounded_sam2_timeout_seconds: int = int(
        os.getenv("GROUNDED_SAM2_TIMEOUT_SECONDS", "600")
    )
    max_upload_bytes: int = int(os.getenv("MAX_UPLOAD_BYTES", str(10 * 1024 * 1024)))


settings = Settings()
