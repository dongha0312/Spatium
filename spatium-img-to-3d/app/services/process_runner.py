from __future__ import annotations

import asyncio
import os
import signal
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence


class ProcessStartError(RuntimeError):
    pass


class ProcessTimeoutError(TimeoutError):
    pass


@dataclass(frozen=True)
class ProcessResult:
    returncode: int
    stdout: bytes
    stderr: bytes


class AsyncProcessRunner:
    """Run one subprocess and always reap it on timeout or request cancellation."""

    async def run(
        self,
        args: Sequence[str],
        *,
        timeout_seconds: float,
        cwd: Path | None = None,
        env: Mapping[str, str] | None = None,
    ) -> ProcessResult:
        spawn_options = {
            "cwd": cwd,
            "env": env,
            "stdout": asyncio.subprocess.PIPE,
            "stderr": asyncio.subprocess.PIPE,
        }
        if os.name != "nt":
            spawn_options["start_new_session"] = True

        try:
            process = await asyncio.create_subprocess_exec(*args, **spawn_options)
        except OSError as exc:
            raise ProcessStartError("Could not start subprocess.") from exc

        try:
            stdout, stderr = await asyncio.wait_for(
                process.communicate(), timeout=timeout_seconds
            )
        except asyncio.TimeoutError as exc:
            await self._kill_and_reap(process)
            raise ProcessTimeoutError("Subprocess timed out.") from exc
        except asyncio.CancelledError:
            await self._kill_and_reap(process)
            raise

        return ProcessResult(
            returncode=int(process.returncode or 0),
            stdout=stdout,
            stderr=stderr,
        )

    @staticmethod
    async def _kill_and_reap(process: asyncio.subprocess.Process) -> None:
        if process.returncode is None:
            try:
                if os.name != "nt":
                    os.killpg(process.pid, signal.SIGKILL)
                else:
                    process.kill()
            except ProcessLookupError:
                pass
        try:
            await process.communicate()
        except ProcessLookupError:
            pass
