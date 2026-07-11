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

Default free provider:

```env
IMAGE_TO_3D_PROVIDER=huggingface
HF_SPACE_ID=frogleo/Image-to-3D
```

Optional paid provider:

```env
IMAGE_TO_3D_PROVIDER=stability
STABILITY_API_KEY=sk-...
```
