import os
from pathlib import Path

import uvicorn
from dotenv import load_dotenv


BASE_DIR = Path(__file__).resolve().parent


def _env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name, str(default)).strip().lower()
    if value in {"1", "true", "yes", "on"}:
        return True
    if value in {"0", "false", "no", "off"}:
        return False
    raise RuntimeError(f"{name} must be a boolean value.")


def main() -> None:
    env_file = BASE_DIR / ".env"
    load_dotenv(env_file)
    host = os.getenv("HOST", "127.0.0.1")
    try:
        port = int(os.getenv("PORT", "8000"))
    except ValueError as exc:
        raise RuntimeError("PORT must be an integer.") from exc
    if not 1 <= port <= 65535:
        raise RuntimeError("PORT must be between 1 and 65535.")
    reload = _env_bool("RELOAD", False)

    uvicorn.run(
        "app.main:app",
        host=host,
        port=port,
        reload=reload,
        env_file=str(env_file),
    )


if __name__ == "__main__":
    main()
