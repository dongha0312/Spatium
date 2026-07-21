from __future__ import annotations

import asyncio
import unittest

from app.services.concurrency import GpuConcurrencyLimiter


class GpuConcurrencyLimiterTests(unittest.IsolatedAsyncioTestCase):
    async def test_limits_gpu_work_to_one_request(self) -> None:
        limiter = GpuConcurrencyLimiter(1)
        active = 0
        maximum_active = 0

        async def worker() -> None:
            nonlocal active, maximum_active
            async with limiter.slot():
                active += 1
                maximum_active = max(maximum_active, active)
                await asyncio.sleep(0.01)
                active -= 1

        await asyncio.gather(*(worker() for _ in range(5)))
        self.assertEqual(maximum_active, 1)

    async def test_cancelled_waiter_does_not_consume_a_slot(self) -> None:
        limiter = GpuConcurrencyLimiter(1)
        release = asyncio.Event()
        entered = asyncio.Event()

        async def holder() -> None:
            async with limiter.slot():
                entered.set()
                await release.wait()

        holder_task = asyncio.create_task(holder())
        await entered.wait()
        waiter = asyncio.create_task(self._enter_once(limiter))
        await asyncio.sleep(0)
        waiter.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await waiter
        release.set()
        await holder_task
        await asyncio.wait_for(self._enter_once(limiter), timeout=0.5)

    @staticmethod
    async def _enter_once(limiter: GpuConcurrencyLimiter) -> None:
        async with limiter.slot():
            return None
