package com.pknu.spatium_backend.auth;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import org.junit.jupiter.api.Test;

import com.pknu.spatium_backend.exception.ApiException;

class GpuAccessLimiterTest {

    private final GpuAccessLimiter limiter = new GpuAccessLimiter();

    @Test
    void allowsFirstRequestFromAnIp() {
        assertDoesNotThrow(() -> limiter.acquire("10.0.0.1"));
    }

    @Test
    void rejectsSecondConcurrentRequestFromSameIp() {
        limiter.acquire("10.0.0.1");

        ApiException error = assertThrows(ApiException.class, () -> limiter.acquire("10.0.0.1"));
        assertEquals(429, error.getStatusCode());
        assertEquals("AI_ALREADY_IN_PROGRESS", error.getCode());
    }

    @Test
    void allowsNextRequestAfterRelease() {
        limiter.acquire("10.0.0.1");
        limiter.release("10.0.0.1");

        // release가 제대로 동작하지 않으면 해당 IP가 영구히 잠기므로 반드시 확인한다.
        assertDoesNotThrow(() -> limiter.acquire("10.0.0.1"));
    }

    @Test
    void doesNotBlockDifferentIps() {
        limiter.acquire("10.0.0.1");

        assertDoesNotThrow(() -> limiter.acquire("10.0.0.2"));
    }

    @Test
    void releaseOfUnknownIpIsHarmless() {
        assertDoesNotThrow(() -> limiter.release("10.0.0.9"));
    }

    @Test
    void allowsRepeatedSequentialRequests() {
        for (int i = 0; i < 5; i++) {
            limiter.acquire("10.0.0.1");
            limiter.release("10.0.0.1");
        }

        assertDoesNotThrow(() -> limiter.acquire("10.0.0.1"));
    }

    // 동시에 여러 요청이 들어와도 정확히 하나만 통과해야 한다 (compute 원자성 검증)
    @Test
    void onlyOneOfManySimultaneousRequestsSucceeds() throws InterruptedException {
        int threads = 16;
        ExecutorService pool = Executors.newFixedThreadPool(threads);
        CountDownLatch startLine = new CountDownLatch(1);
        CountDownLatch finished = new CountDownLatch(threads);
        AtomicInteger acquired = new AtomicInteger();

        try {
            for (int i = 0; i < threads; i++) {
                pool.submit(() -> {
                    try {
                        startLine.await();
                        limiter.acquire("10.0.0.1");
                        acquired.incrementAndGet();
                    } catch (ApiException expected) {
                        // 429 : 정상적으로 차단된 경우
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                    } finally {
                        finished.countDown();
                    }
                });
            }

            startLine.countDown();
            assertTrue(finished.await(5, TimeUnit.SECONDS), "테스트 스레드가 시간 내에 끝나지 않았습니다.");
            assertEquals(1, acquired.get());
        } finally {
            pool.shutdownNow();
        }
    }
}
