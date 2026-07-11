import os

import uvicorn


def main() -> None:
    host = os.getenv("HOST", "127.0.0.1")
    port = int(os.getenv("PORT", "8000"))
    reload = os.getenv("RELOAD", "true").lower() in {"1", "true", "yes", "on"}

    uvicorn.run(
        "app.main:app",
        host=host,
        port=port,
        reload=reload,
        env_file=".env",
    )


if __name__ == "__main__":
    main()
