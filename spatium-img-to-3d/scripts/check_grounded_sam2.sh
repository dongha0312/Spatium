#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="${ROOT_DIR}/.venv-segmentation/bin/python"

test -x "${PYTHON}" || { echo "Missing ${PYTHON}" >&2; exit 1; }
test -f "${ROOT_DIR}/scripts/run_grounded_sam2.py" || { echo "Missing runner" >&2; exit 1; }
test -f "${ROOT_DIR}/vendor/weights/opus-mt-ko-en/config.json" || { echo "Missing OPUS-MT model" >&2; exit 1; }
test -f "${ROOT_DIR}/vendor/weights/grounding-dino-tiny/config.json" || { echo "Missing GroundingDINO model" >&2; exit 1; }
test -f "${ROOT_DIR}/vendor/weights/sam2.1-hiera-small/config.json" || { echo "Missing SAM2 model" >&2; exit 1; }

"${PYTHON}" - <<'PY'
import torch
import transformers
from packaging.version import Version
from transformers import Sam2Model, Sam2Processor

print(f"torch={torch.__version__}")
print(f"transformers={transformers.__version__}")
if Version(torch.__version__.split("+")[0]) < Version("2.6.0"):
    raise RuntimeError(
        "torch>=2.6.0 is required to safely load the OPUS-MT pytorch_model.bin weights"
    )
print(f"cuda_available={torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"gpu={torch.cuda.get_device_name(0)}")
print("GroundingDINO + SAM2 environment: OK")
PY
