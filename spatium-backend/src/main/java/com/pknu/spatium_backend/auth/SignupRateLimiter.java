package com.pknu.spatium_backend.auth;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.springframework.stereotype.Component;

import com.pknu.spatium_backend.exception.ApiException;

// 회원가입 요청 rate limit : 같은 IP의 과도한 가입 시도를 차단
//  - 이메일 존재 여부 열거(enumeration) 방지 : "이미 가입된 이메일입니다" 응답을
//    무제한으로 받아 가입 여부를 수집하는 것을 시도 횟수 제한으로 완화한다.
//  - 대량 계정 자동 생성(스팸 가입) 완화 효과도 있다.
//  - LoginAttemptLimiter와 동일하게 인메모리 방식 : 단일 서버 배포 기준이며
//    다중 서버로 확장하면 Redis 등 공유 저장소로 교체 필요
@Component
public class SignupRateLimiter {

    // 윈도우당 허용 시도 횟수
    //  - 같은 공유기/학내망(NAT)에서 여러 명이 가입할 수 있으므로 너무 낮게 잡지 않는다.
    private static final int MAX_ATTEMPTS = 10;

    // 시도 횟수를 세는 시간 윈도우 (경과 시 카운터 리셋)
    private static final Duration WINDOW = Duration.ofMinutes(10);

    // 메모리 보호용 상한 : 초과 시 만료된 기록을 정리
    private static final int CLEANUP_THRESHOLD = 10_000;

    private final Map<String, Window> windows = new ConcurrentHashMap<>();

    // 가입 시도 전에 호출 : 시도를 기록하고, 윈도우 내 허용 횟수를 넘으면 429
    public void checkAndRecord(String clientIp) {
        cleanupIfNeeded();

        Window window = windows.compute(clientIp, (k, w) -> {
            Instant now = Instant.now();
            if (w == null || w.isExpired(now)) {
                return new Window(1, now);
            }
            return new Window(w.count() + 1, w.startedAt());
        });

        if (window.count() > MAX_ATTEMPTS) {
            throw new ApiException(429, "TOO_MANY_ATTEMPTS",
                    "요청이 너무 많습니다. 잠시 후 다시 시도해주세요.");
        }
    }

    private void cleanupIfNeeded() {
        if (windows.size() < CLEANUP_THRESHOLD) {
            return;
        }
        Instant now = Instant.now();
        windows.entrySet().removeIf(entry -> entry.getValue().isExpired(now));
    }

    private record Window(int count, Instant startedAt) {
        boolean isExpired(Instant now) {
            return now.isAfter(startedAt.plus(WINDOW));
        }
    }
}
