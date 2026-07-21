from __future__ import annotations

import asyncio
import os
import sys
import tempfile
import unittest
from pathlib import Path

from app.services.process_runner import AsyncProcessRunner, ProcessTimeoutError


class AsyncProcessRunnerTests(unittest.IsolatedAsyncioTestCase):
    async def test_captures_output(self) -> None:
        result = await AsyncProcessRunner().run(
            [sys.executable, "-c", "import sys; print('out'); print('err', file=sys.stderr)"],
            timeout_seconds=2,
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), b"out")
        self.assertEqual(result.stderr.strip(), b"err")

    async def test_timeout_kills_and_reaps_process(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            pid_file = Path(directory) / "pid"
            code = (
                "import os,time,pathlib; "
                f"pathlib.Path({str(pid_file)!r}).write_text(str(os.getpid())); "
                "time.sleep(30)"
            )
            with self.assertRaises(ProcessTimeoutError):
                await AsyncProcessRunner().run(
                    [sys.executable, "-c", code], timeout_seconds=0.2
                )
            pid = int(pid_file.read_text())
            self.assertFalse(await self._process_exists(pid))

    async def test_cancellation_kills_and_reaps_process(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            pid_file = Path(directory) / "pid"
            code = (
                "import os,time,pathlib; "
                f"pathlib.Path({str(pid_file)!r}).write_text(str(os.getpid())); "
                "time.sleep(30)"
            )
            task = asyncio.create_task(
                AsyncProcessRunner().run(
                    [sys.executable, "-c", code], timeout_seconds=30
                )
            )
            for _ in range(100):
                if pid_file.exists():
                    break
                await asyncio.sleep(0.01)
            self.assertTrue(pid_file.exists())
            pid = int(pid_file.read_text())
            task.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await task
            self.assertFalse(await self._process_exists(pid))

    @staticmethod
    async def _process_exists(pid: int) -> bool:
        for _ in range(50):
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return False
            await asyncio.sleep(0.01)
        return True
