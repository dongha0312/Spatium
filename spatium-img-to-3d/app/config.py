from pathlib import Path
from typing import Final
import os

from dotenv import load_dotenv


BASE_DIR: Final = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")
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


def _env_path(name: str, default: Path) -> Path:
    path = Path(os.getenv(name, str(default))).expanduser()
    return path if path.is_absolute() else BASE_DIR / path


def _env_int(name: str, default: int, *, minimum: int = 1) -> int:
    try:
        value = int(os.getenv(name, str(default)))
    except ValueError as exc:
        raise RuntimeError(f"{name} must be an integer.") from exc
    if value < minimum:
        raise RuntimeError(f"{name} must be at least {minimum}.")
    return value


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, str(default)))
    except ValueError as exc:
        raise RuntimeError(f"{name} must be a number.") from exc


def _env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name, str(default)).strip().lower()
    if value in {"1", "true", "yes", "on"}:
        return True
    if value in {"0", "false", "no", "off"}:
        return False
    raise RuntimeError(f"{name} must be a boolean value.")


class Settings:
    image_to_3d_provider: str = os.getenv("IMAGE_TO_3D_PROVIDER", "local_triposr")
    local_triposr_repo_dir: Path = _env_path("LOCAL_TRIPOSR_REPO_DIR", DEFAULT_TRIPOSR_REPO)
    local_triposr_python: Path = _env_path("LOCAL_TRIPOSR_PYTHON", DEFAULT_TRIPOSR_PYTHON)
    local_triposr_model_path: str = str(
        _env_path("LOCAL_TRIPOSR_MODEL_PATH", DEFAULT_TRIPOSR_MODEL)
    )
    local_triposr_device: str = os.getenv(
        "LOCAL_TRIPOSR_DEVICE", "cpu" if IS_WINDOWS else "cuda:0"
    )
    local_triposr_timeout_seconds: int = _env_int("LOCAL_TRIPOSR_TIMEOUT_SECONDS", 600)
    local_sf3d_repo_dir: Path = _env_path("LOCAL_SF3D_REPO_DIR", DEFAULT_SF3D_REPO)
    local_sf3d_python: Path = _env_path("LOCAL_SF3D_PYTHON", DEFAULT_SF3D_PYTHON)
    local_sf3d_model_path: str = str(_env_path("LOCAL_SF3D_MODEL_PATH", DEFAULT_SF3D_MODEL))
    local_sf3d_device: str = os.getenv("LOCAL_SF3D_DEVICE", "cuda")
    local_sf3d_timeout_seconds: int = _env_int("LOCAL_SF3D_TIMEOUT_SECONDS", 600)
    yolo_segmentation_model: str = str(
        _env_path("YOLO_SEGMENTATION_MODEL", DEFAULT_YOLO_MODEL)
    )
    yolo_segmentation_device: str = os.getenv("YOLO_SEGMENTATION_DEVICE", "auto")
    yolo_segmentation_confidence: float = _env_float("YOLO_SEGMENTATION_CONFIDENCE", 0.25)
    grounded_sam2_python: Path = _env_path(
        "GROUNDED_SAM2_PYTHON", DEFAULT_SEGMENTATION_PYTHON
    )
    grounding_dino_model: Path = _env_path(
        "GROUNDING_DINO_MODEL", DEFAULT_GROUNDING_DINO_MODEL
    )
    sam2_model: Path = _env_path("SAM2_MODEL", DEFAULT_SAM2_MODEL)
    translation_model: Path = _env_path("KO_EN_TRANSLATION_MODEL", DEFAULT_TRANSLATION_MODEL)
    grounded_sam2_device: str = os.getenv("GROUNDED_SAM2_DEVICE", "cuda")
    grounding_dino_box_threshold: float = _env_float("GROUNDING_DINO_BOX_THRESHOLD", 0.30)
    grounding_dino_text_threshold: float = _env_float("GROUNDING_DINO_TEXT_THRESHOLD", 0.25)
    grounded_sam2_timeout_seconds: int = _env_int("GROUNDED_SAM2_TIMEOUT_SECONDS", 600)
    auto_orient_glb_for_threejs: bool = _env_bool("AUTO_ORIENT_GLB_FOR_THREEJS", True)
    glb_rotation_x_degrees: float = _env_float("GLB_ROTATION_X_DEGREES", -90.0)
    max_upload_bytes: int = _env_int("MAX_UPLOAD_BYTES", 30 * 1024 * 1024)
    max_image_pixels: int = _env_int("MAX_IMAGE_PIXELS", 40_000_000)
    gpu_max_concurrency: int = _env_int("GPU_MAX_CONCURRENCY", 1)


settings = Settings()
