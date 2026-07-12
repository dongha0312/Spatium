# Image to 3D FastAPI

Single-image to 3D backend. The default provider is the public Hugging Face Space `frogleo/Image-to-3D`, which returns a `.glb` model through the Gradio API.

## Setup

```powershell
$env:UV_CACHE_DIR=".uv-cache"
uv sync
Copy-Item .env.example .env
notepad .env
uv run uvicorn app.main:app --reload --port 8000 --env-file .env
```

Open the UI:

```text
http://127.0.0.1:8000
```

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
  -F "image=@C:\path\to\object.png" `
  -F "foreground_ratio=0.85" `
  -F "mc_resolution=256" `
  -F "remove_background=true"
```

The response contains a `download_url`, for example:

```json
{
  "id": "5f5d8dc9c69b4d6fb6b1dc516cfa36a3",
  "provider": "stability",
  "format": "glb",
  "download_url": "/v1/assets/5f5d8dc9c69b4d6fb6b1dc516cfa36a3.glb"
}
```

## Notes

- Hugging Face public Spaces are free to try, but they can sleep, queue, rate limit, or change availability.
- The bundled default does not require `STABILITY_API_KEY`.
- Best input: a single centered object, plain background, no heavy crop, PNG/JPEG/WebP.
- Output quality depends heavily on the source image. Product/object images work better than scenes.
- Keep generated files out of git; they are written to `storage/outputs/`.

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
  -F "image=@/path/to/room.jpg" \
  -F "segmentation_provider=grounded_sam2" \
  -F "object_query=회색 사무용 의자"
```

Generate a GLB in one request by adding the same fields to
`/v1/image-to-3d` and selecting either `provider=local_triposr` or
`provider=local_stable_fast_3d`. If a user already confirmed the transparent
PNG preview, upload that PNG with `remove_background=false` to avoid running
segmentation twice.
