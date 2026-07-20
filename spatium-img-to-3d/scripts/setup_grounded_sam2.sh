#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${ROOT_DIR}/.venv-segmentation"
WEIGHTS_DIR="${ROOT_DIR}/vendor/weights"

command -v uv >/dev/null 2>&1 || {
  echo "uv is required. Install it first: https://docs.astral.sh/uv/" >&2
  exit 1
}

echo "Creating isolated GroundingDINO + SAM2 environment"
uv python install 3.11
uv venv --python 3.11 --clear "${VENV_DIR}"

echo "Installing CUDA PyTorch"
uv pip install --python "${VENV_DIR}/bin/python" \
  --index-url https://download.pytorch.org/whl/cu124 \
  "torch==2.6.0" "torchvision==0.21.0"

echo "Installing segmentation and translation dependencies"
uv pip install --python "${VENV_DIR}/bin/python" \
  "transformers>=4.57,<5" "huggingface-hub>=0.34" \
  "sentencepiece>=0.2" "sacremoses>=0.1" "protobuf>=5" "accelerate>=1" \
  "pillow>=10" "numpy<2.1" "safetensors>=0.4"

mkdir -p "${WEIGHTS_DIR}"
export ROOT_DIR
"${VENV_DIR}/bin/python" - <<'PY'
import os
from pathlib import Path
from huggingface_hub import snapshot_download

root = Path(os.environ["ROOT_DIR"])
models = {
    "Helsinki-NLP/opus-mt-ko-en": root / "vendor/weights/opus-mt-ko-en",
    "IDEA-Research/grounding-dino-tiny": root / "vendor/weights/grounding-dino-tiny",
    "facebook/sam2.1-hiera-small": root / "vendor/weights/sam2.1-hiera-small",
}
for repo_id, local_dir in models.items():
    print(f"Downloading {repo_id} -> {local_dir}", flush=True)
    snapshot_download(
        repo_id=repo_id,
        local_dir=local_dir,
        ignore_patterns=["*.msgpack", "*.h5", "*.ot", "*.onnx"],
    )
PY

echo
echo "Installation complete. Checking local files..."
bash "${ROOT_DIR}/scripts/check_grounded_sam2.sh"
