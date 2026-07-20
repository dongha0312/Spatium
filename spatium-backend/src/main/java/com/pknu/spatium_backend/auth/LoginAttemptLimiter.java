package com.pknu.spatium_backend.auth;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.springframework.stereotype.Component;

import com.pknu.spatium_backend.exception.ApiException;

// 로그인 brute-force 방어 : 같은 (이메일+IP) 조합이 연속 실패하면 일정 시간 잠금
//  - 인메모리 방식 : 단일 서버 배포 기준. 서버 재시작 시 초기화됨
//  - 다중 서버로 확장하면 Redis 등 공유 저장소로 교체 필요
@Component
public class LoginAttemptLimiter {

    // 연속 실패 허용 횟수 (이 횟수 도달 시 잠금)
    private static final int MAX_FAILURES = 5;

    // 잠금 시간
    private static final Duration LOCK_DURATION = Duration.ofMinutes(5);

    // 실패 기록 유지 시간 (이 시간 동안 추가 실패가 없으면 카운터 리셋)
    private static final Duration FAILURE_WINDOW = Duration.ofMinutes(10);

    // 메모리 보호용 상한 : 초과 시 만료된 기록을 정리
    private static final int CLEANUP_THRESHOLD = 10_000;

    private final Map<String, Attempt> attempts = new ConcurrentHashMap<>();

    // 로그인 시도 전에 호출 : 잠금 상태면 429
    public void checkNotBlocked(String key) {
        Attempt attempt = attempts.get(key);
        if (attempt == null) {
            return;
        }

        if (attempt.lockedUntil != null) {
            if (Instant.now().isBefore(attempt.lockedUntil)) {
                throw new ApiException(429, "TOO_MANY_ATTEMPTS",
                        "로그인 시도가 너무 많습니다. 잠시 후 다시 시도해주세요.");
            }
            // 잠금 시간이 지났으면 기록 초기화
            attempts.remove(key);
        }
    }

    // 로그인 실패 시 호출
    public void recordFailure(String key) {
        cleanupIfNeeded();

        attempts.compute(key, (k, attempt) -> {
            Instant now = Instant.now();

            if (attempt == null || attempt.isExpired(now)) {
                return new Attempt(1, now, null);
            }

            int failures = attempt.failures + 1;
            Instant lockedUntil = failures >= MAX_FAILURES
                    ? now.plus(LOCK_DURATION)
                    : null;

            return new Attempt(failures, now, lockedUntil);
        });
    }

    // 로그인 성공 시 호출 : 실패 기록 초기화
    public void recordSuccess(String key) {
        attempts.remove(key);
    }

    private void cleanupIfNeeded() {
        if (attempts.size() < CLEANUP_THRESHOLD) {
            return;
        }
        Instant now = Instant.now();
        attempts.entrySet().removeIf(entry -> entry.getValue().isExpired(now));
    }

    private record Attempt(int failures, Instant lastFailureAt, Instant lockedUntil) {
        boolean isExpired(Instant now) {
            if (lockedUntil != null) {
                return now.isAfter(lockedUntil);
            }
            return now.isAfter(lastFailureAt.plus(FAILURE_WINDOW));
        }
    }
}
