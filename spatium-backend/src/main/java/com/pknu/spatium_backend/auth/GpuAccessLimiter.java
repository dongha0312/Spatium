package com.pknu.spatium_backend.auth;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;

import org.springframework.stereotype.Component;

import com.pknu.spatium_backend.exception.ApiException;

// GPU 작업(img-to-3d, remove-background) 동시 실행 제한 : 같은 IP는 한 번에 한 작업만
//  - 파이썬 서버에도 GpuConcurrencyLimiter(GPU_MAX_CONCURRENCY=1)가 있어 GPU 자체는
//    이미 직렬화되지만, 초과 요청은 거절되지 않고 큐에서 무한정 대기한다.
//    그래서 한 사용자가 요청을 연달아 던지면 큐를 독점해 다른 사용자가 계속 밀린다.
//    이 클래스는 그 앞단에서 "이미 진행 중이면 즉시 429"로 끊어 큐 독점을 막는다.
//  - LoginAttemptLimiter/SignupRateLimiter와 동일하게 인메모리 방식 : 단일 서버 배포
//    기준이며 다중 서버로 확장하면 Redis 등 공유 저장소로 교체 필요
//  - (주의) 학내망/공유기(NAT)처럼 여러 명이 같은 IP를 쓰는 환경에서는 한 명이 작업 중일 때
//    같은 IP의 다른 사용자도 함께 막힌다. IP 기준 제한의 의도된 트레이드오프다.
@Component
public class GpuAccessLimiter {

    // 점유 기록이 이 시간을 넘으면 비정상(release 누락 등)으로 보고 새 요청에 자리를 넘긴다.
    //  - 정상 작업의 상한은 spatium.ai.request-timeout(기본 PT15M)이므로 그보다 넉넉히 잡는다.
    //  - 이 안전장치가 없으면 예기치 못한 경로로 release가 빠졌을 때 해당 IP가 영구히 잠긴다.
    private static final Duration STALE_AFTER = Duration.ofMinutes(20);

    // 메모리 보호용 상한 : 초과 시 만료(stale)된 기록을 정리
    private static final int CLEANUP_THRESHOLD = 10_000;

    // key = 클라이언트 IP, value = 점유 시작 시각
    private final Map<String, Instant> inProgress = new ConcurrentHashMap<>();

    // GPU 작업 시작 전에 호출 : 이미 진행 중인 작업이 있으면 429
    //  - 반드시 try/finally로 감싸 release(clientIp)가 호출되도록 할 것
    public void acquire(String clientIp) {
        cleanupIfNeeded();

        Instant now = Instant.now();
        AtomicBoolean acquired = new AtomicBoolean(false);

        // compute로 원자적으로 처리 : 동시 요청이 둘 다 통과하는 race condition 방지
        inProgress.compute(clientIp, (key, startedAt) -> {
            if (startedAt == null || isStale(startedAt, now)) {
                acquired.set(true);
                return now;
            }
            // 진행 중인 작업이 있으면 기존 기록을 그대로 유지 (시작 시각을 갱신하지 않음)
            return startedAt;
        });

        if (!acquired.get()) {
            throw new ApiException(429, "AI_ALREADY_IN_PROGRESS",
                    "이미 생성 중인 작업이 있습니다. 완료 후 다시 시도해주세요.");
        }
    }

    // GPU 작업 종료 후 호출 (성공/실패 무관) : 점유 해제
    public void release(String clientIp) {
        inProgress.remove(clientIp);
    }

    private boolean isStale(Instant startedAt, Instant now) {
        return now.isAfter(startedAt.plus(STALE_AFTER));
    }

    private void cleanupIfNeeded() {
        if (inProgress.size() < CLEANUP_THRESHOLD) {
            return;
        }
        Instant now = Instant.now();
        inProgress.entrySet().removeIf(entry -> isStale(entry.getValue(), now));
    }
}
