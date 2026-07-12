#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="${LOCAL_SF3D_REPO_DIR:-$ROOT_DIR/vendor/stable-fast-3d}"
MODEL_DIR="${LOCAL_SF3D_MODEL_PATH:-$ROOT_DIR/vendor/weights/stable-fast-3d}"
PYTHON="${LOCAL_SF3D_PYTHON:-$ROOT_DIR/.venv-sf3d/bin/python}"

test -x "$PYTHON" || { echo "Missing $PYTHON"; exit 1; }
test -f "$REPO_DIR/run.py" || { echo "Missing $REPO_DIR/run.py"; exit 1; }
test -f "$MODEL_DIR/model.safetensors" || { echo "Missing model.safetensors"; exit 1; }
test -f "$MODEL_DIR/config.yaml" || { echo "Missing config.yaml"; exit 1; }

cd "$REPO_DIR"
"$PYTHON" -c "import torch; import sf3d; print('torch', torch.__version__); print('cuda', torch.cuda.is_available()); print('device', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'cpu')"
echo "Local Stable Fast 3D is ready."
