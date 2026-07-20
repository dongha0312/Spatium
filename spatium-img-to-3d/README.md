# Image to 3D FastAPI

Single-image to 3D backend. The active providers are local TripoSR and local
Stable Fast 3D, with YOLO or GroundingDINO+SAM2 segmentation.

## Setup

```bash
uv sync
cp .env.example .env
uv run python run.py
```

Set a non-empty `AI_INTERNAL_API_KEY` in `.env`. Spring sends the same value in
the `X-Internal-Api-Key` header. The key must never be committed, returned in an
API response, or written to normal request logs. `RELOAD` defaults to `false`
so the GPU worker is not duplicated in production.

You can also run the server with:

```powershell
uv run python run.py
```

On Windows, double-click or run:

```powershell
.\run_server.bat
```

## Local Model

For a local model instead of a public Hugging Face Space, install TripoSR into a separate environment:

```powershell
.\scripts\setup_local_triposr.ps1
```

On Windows, TripoSR needs Microsoft C++ Build Tools to compile `torchmcubes`. If the setup script reports missing `cl.exe` or `nmake.exe`, install the build tools:

```powershell
.\scripts\install_windows_cpp_build_tools.ps1
```

Restart your terminal after the installer finishes, then run `setup_local_triposr.ps1` again.

Then restart the server and choose `로컬 TripoSR` in the UI. You can also force local mode for the whole server:

```powershell
.\run_server_local.bat
```

The default local mode uses CPU because Windows can have an NVIDIA driver without the CUDA Toolkit needed to compile native extensions. For GPU local mode, install CUDA Toolkit 12.1, run setup again, and start:

```powershell
.\scripts\install_cuda_toolkit_12_1.ps1
.\scripts\setup_local_triposr.ps1
```

Then run:

```powershell
.\run_server_local_gpu.bat
```

Check the local model environment:

```powershell
.\scripts\check_local_triposr.ps1
```

## API

Health check:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/health
```

Generate a GLB:

```powershell
curl.exe -X POST "http://127.0.0.1:8000/v1/image-to-3d" `
  -H "X-Internal-Api-Key: $env:AI_INTERNAL_API_KEY" `
  -F "image=@C:\path\to\object.png" `
  -F "foreground_ratio=0.85" `
  -F "mc_resolution=256" `
  -F "remove_background=true" `
  --output generated-model.glb
```

The response body is the GLB binary. Small UI metadata is returned as compact
UTF-8 JSON encoded with unpadded base64url in `X-Spatium-AI-Metadata`. There is
no result id or follow-up download URL.

## Notes

- GPU work is limited to one concurrent request per API worker by default.
  Keep a single Uvicorn worker when using one GPU; process-local semaphores do
  not coordinate across multiple workers.
- Best input: a single centered object, plain background, no heavy crop, PNG/JPEG/WebP.
- Output quality depends heavily on the source image. Product/object images work better than scenes.
- Request-scoped files are removed immediately from `storage/tmp/`.
- Response GLB and PNG files are streamed with `FileResponse` and deleted by a
  best-effort background cleanup after the response completes. A process crash
  can leave an orphan file; cleanup failure is logged and does not cancel an
  otherwise successful AI response.

## Providers

The UI can select either local provider. Existing clients that omit the
`provider` form field continue to use TripoSR.

Default local TripoSR provider:

```env
IMAGE_TO_3D_PROVIDER=local_triposr
```

Free local Stable Fast 3D provider:

1. Accept the gated model license at
   <https://huggingface.co/stabilityai/stable-fast-3d>.
2. Copy `.env.example` to `.env` and put your Hugging Face read token there:

```env
HF_TOKEN=hf_your_real_token
```

3. Run the one-time installer in WSL:

```bash
chmod +x scripts/setup_local_sf3d.sh scripts/check_local_sf3d.sh
./scripts/setup_local_sf3d.sh
./scripts/check_local_sf3d.sh
```

4. Restart the API and choose `Stable Fast 3D (무료 로컬 모델)` in the UI.

The token is only used to download the gated model weights. Generation then
runs on the server GPU and does not call or charge the Stability Platform API.
Do not use `STABILITY_API_KEY` for this local provider.

Optional defaults can be changed in `.env`:

```env
LOCAL_SF3D_REPO_DIR=vendor/stable-fast-3d
LOCAL_SF3D_PYTHON=.venv-sf3d/bin/python
LOCAL_SF3D_MODEL_PATH=vendor/weights/stable-fast-3d
LOCAL_SF3D_DEVICE=cuda
```

## GroundingDINO + SAM2 segmentation

YOLO remains the default, so existing API clients keep working unchanged.
For natural-language object selection (including Korean), install the isolated
segmentation environment once in WSL:

```bash
chmod +x scripts/setup_grounded_sam2.sh scripts/check_grounded_sam2.sh
bash scripts/setup_grounded_sam2.sh
bash scripts/check_grounded_sam2.sh
```

This downloads three free local models: OPUS-MT Korean-to-English translation,
GroundingDINO Tiny detection, and SAM2.1 Hiera Small segmentation. The API runs
them in a separate process, which exits before TripoSR or Stable Fast 3D starts
and releases its GPU memory.

Preview a Korean natural-language target:

```bash
curl -X POST http://127.0.0.1:8000/v1/remove-background \
  -H "X-Internal-Api-Key: ${AI_INTERNAL_API_KEY}" \
  -F "image=@/path/to/room.jpg" \
  -F "segmentation_provider=grounded_sam2" \
  -F "object_query=회색 사무용 의자" \
  --output segmented.png
```

Generate a GLB in one request by adding the same fields to
`/v1/image-to-3d` and selecting either `provider=local_triposr` or
`provider=local_stable_fast_3d`. If a user already confirmed the transparent
PNG preview, upload that PNG with `remove_background=false` to avoid running
segmentation twice.
