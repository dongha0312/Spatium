#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="${LOCAL_SF3D_REPO_DIR:-$ROOT_DIR/vendor/stable-fast-3d}"
MODEL_DIR="${LOCAL_SF3D_MODEL_PATH:-$ROOT_DIR/vendor/weights/stable-fast-3d}"
VENV_DIR="$ROOT_DIR/.venv-sf3d"
PYTHON_VERSION="${SF3D_PYTHON_VERSION:-3.11}"
TORCH_INDEX_URL="${SF3D_TORCH_INDEX_URL:-https://download.pytorch.org/whl/cu124}"
TORCH_VERSION="${SF3D_TORCH_VERSION:-2.4.1}"
TORCHVISION_VERSION="${SF3D_TORCHVISION_VERSION:-0.19.1}"

if [[ -f "$ROOT_DIR/.env" && -z "${HF_TOKEN:-}" ]]; then
  HF_TOKEN="$(grep -m1 '^HF_TOKEN=' "$ROOT_DIR/.env" | cut -d= -f2- || true)"
  export HF_TOKEN
fi

if [[ -z "${HF_TOKEN:-}" || "$HF_TOKEN" == "hf_your_token_here" ]]; then
  echo "HF_TOKEN is missing."
  echo "1) Accept the license: https://huggingface.co/stabilityai/stable-fast-3d"
  echo "2) Put HF_TOKEN=hf_... in $ROOT_DIR/.env"
  exit 1
fi

command -v git >/dev/null || { echo "git is required."; exit 1; }
command -v uv >/dev/null || { echo "uv is required. Install it from https://docs.astral.sh/uv/"; exit 1; }

mkdir -p "$ROOT_DIR/vendor" "$ROOT_DIR/vendor/weights"
if [[ ! -d "$REPO_DIR/.git" ]]; then
  git clone https://github.com/Stability-AI/stable-fast-3d.git "$REPO_DIR"
else
  echo "Using existing repository: $REPO_DIR"
fi

uv python install "$PYTHON_VERSION"
if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  uv venv --python "$PYTHON_VERSION" "$VENV_DIR"
else
  echo "Using existing virtual environment: $VENV_DIR"
fi
SF3D_PYTHON="$VENV_DIR/bin/python"

uv pip install --python "$SF3D_PYTHON" --upgrade wheel ninja "setuptools==69.5.1"
uv pip install --python "$SF3D_PYTHON" \
  --index-url "$TORCH_INDEX_URL" \
  "torch==$TORCH_VERSION" "torchvision==$TORCHVISION_VERSION"
# requirements.txt contains local paths such as ./texture_baker and
# ./uv_unwrapper. Resolve them from the Stable Fast 3D repository, not from
# the FastAPI project root.
pushd "$REPO_DIR" >/dev/null
# texture_baker and uv_unwrapper import torch from setup.py. Build them in the
# prepared SF3D environment so they can see the PyTorch installed above.
rm -rf texture_baker/build uv_unwrapper/build
uv pip install --python "$SF3D_PYTHON" --no-build-isolation -r requirements.txt

# These packages are native PyTorch extensions. uv may otherwise reuse a wheel
# compiled against an older Torch ABI after Torch is upgraded, which causes
# undefined-symbol errors at import time. Rebuild both from source every time.
uv pip uninstall --python "$SF3D_PYTHON" uv-unwrapper texture-baker || true
rm -rf uv_unwrapper/build texture_baker/build
UV_NO_CACHE=1 uv pip install --python "$SF3D_PYTHON" \
  --no-build-isolation ./uv_unwrapper ./texture_baker
popd >/dev/null

"$SF3D_PYTHON" -c "from uv_unwrapper import Unwrapper; from texture_baker import TextureBaker; print('native SF3D extensions: ok')"

"$VENV_DIR/bin/huggingface-cli" download stabilityai/stable-fast-3d \
  --local-dir "$MODEL_DIR"

"$SF3D_PYTHON" -c "import torch; print('torch', torch.__version__); print('cuda', torch.cuda.is_available()); print('device', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'cpu')"
test -f "$MODEL_DIR/model.safetensors"
test -f "$MODEL_DIR/config.yaml"

echo "Stable Fast 3D installation complete."
echo "Restart the FastAPI server and select 'Stable Fast 3D (무료 로컬 모델)'."
