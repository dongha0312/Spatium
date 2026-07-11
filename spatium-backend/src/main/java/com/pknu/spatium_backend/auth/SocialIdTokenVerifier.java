package com.pknu.spatium_backend.auth;

import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.Key;
import java.time.Duration;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.pknu.spatium_backend.exception.ApiException;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.ProtectedHeader;
import io.jsonwebtoken.security.Jwk;
import io.jsonwebtoken.security.JwkSet;
import io.jsonwebtoken.security.Jwks;
import lombok.extern.slf4j.Slf4j;

// 소셜 로그인 ID Token 서버측 검증기
//  - 클라이언트가 보낸 email/providerUserId를 신뢰하지 않고,
//    provider가 발급한 ID Token(JWT)의 서명/iss/aud/만료를 서버가 직접 검증한다.
//  - 서명 검증용 공개키는 각 provider의 JWKS 엔드포인트에서 받아 캐시한다.
@Component
@Slf4j
public class SocialIdTokenVerifier {

    // 검증 성공 시 반환되는 사용자 정보 (sub = provider쪽 고유 사용자 ID)
    public record VerifiedSocialUser(String provider, String providerUserId, String email) {
    }

    private static final String GOOGLE_JWKS_URI = "https://www.googleapis.com/oauth2/v3/certs";
    private static final Set<String> GOOGLE_ISSUERS = Set.of("https://accounts.google.com", "accounts.google.com");

    private static final String APPLE_JWKS_URI = "https://appleid.apple.com/auth/keys";
    private static final Set<String> APPLE_ISSUERS = Set.of("https://appleid.apple.com");

    // JWKS 캐시 유효 시간 (구글/애플 모두 키를 주기적으로 회전하므로 캐시 필요)
    private static final Duration JWKS_CACHE_TTL = Duration.ofHours(6);

    // JWKS 조회 타임아웃 (연결/읽기)
    private static final int JWKS_HTTP_TIMEOUT_MS = 5000;

    private final String googleClientId;
    private final String appleClientId;

    // JWKS URI별 공개키 캐시 (kid -> 공개키)
    private final Map<String, CachedJwks> jwksCache = new ConcurrentHashMap<>();

    public SocialIdTokenVerifier(
            @Value("${spatium.oauth.google.client-id:}") String googleClientId,
            @Value("${spatium.oauth.apple.client-id:}") String appleClientId) {
        this.googleClientId = googleClientId;
        this.appleClientId = appleClientId;
    }

    // provider별 ID Token 검증 진입점
    public VerifiedSocialUser verify(String provider, String idToken) {
        String normalized = provider == null ? "" : provider.trim().toUpperCase();

        return switch (normalized) {
            case "GOOGLE" -> verifyIdToken(normalized, idToken, GOOGLE_JWKS_URI, GOOGLE_ISSUERS, googleClientId);
            case "APPLE" -> verifyIdToken(normalized, idToken, APPLE_JWKS_URI, APPLE_ISSUERS, appleClientId);
            default -> throw new ApiException(400, "UNSUPPORTED_PROVIDER", "지원하지 않는 소셜 provider입니다.");
        };
    }

    private VerifiedSocialUser verifyIdToken(
            String provider, String idToken, String jwksUri, Set<String> issuers, String clientId) {

        if (clientId == null || clientId.isBlank()) {
            // client-id 미설정 provider는 검증 자체가 불가능하므로 차단
            throw new ApiException(400, "UNSUPPORTED_PROVIDER",
                    provider + " 로그인이 서버에 설정되어 있지 않습니다.");
        }

        if (idToken == null || idToken.isBlank()) {
            throw new ApiException(400, "INVALID_SOCIAL_TOKEN", "idToken이 필요합니다.");
        }

        try {
            // 서명/만료 검증 : kid에 해당하는 provider 공개키(JWKS)로 RS256 서명 확인
            Claims claims = Jwts.parser()
                    .keyLocator(header -> locateKey(jwksUri, (ProtectedHeader) header))
                    .build()
                    .parseSignedClaims(idToken)
                    .getPayload();

            // iss 검증 : 토큰 발급자가 해당 provider인지 확인
            if (claims.getIssuer() == null || !issuers.contains(claims.getIssuer())) {
                throw new JwtException("issuer mismatch: " + claims.getIssuer());
            }

            // aud 검증 : 우리 앱(클라이언트 ID)용으로 발급된 토큰인지 확인
            //  - 다른 서비스용으로 발급된 토큰의 재사용(replay)을 차단
            // aud 검증: 콤마로 구분된 허용 클라이언트 ID(웹/iOS 등) 중 하나라도 포함되면 통과
            boolean audOk = false;
            if (claims.getAudience() != null) {
                for (String allowed : clientId.split(",")) {
                    if (claims.getAudience().contains(allowed.trim())) {
                        audOk = true;
                        break;
                    }
                }
            }
            if (!audOk) {
                throw new JwtException("audience mismatch");
            }

            String sub = claims.getSubject();
            if (sub == null || sub.isBlank()) {
                throw new JwtException("subject(sub) is missing");
            }

            return new VerifiedSocialUser(provider, sub, claims.get("email", String.class));
        } catch (JwtException | IllegalArgumentException e) {
            log.warn("소셜 ID Token 검증 실패 (provider={}) : {}", provider, e.getMessage());
            throw new ApiException(401, "INVALID_SOCIAL_TOKEN", "소셜 인증 토큰 검증에 실패했습니다.");
        }
    }

    // JWS 헤더의 kid로 JWKS에서 서명 검증용 공개키를 찾는다.
    private Key locateKey(String jwksUri, ProtectedHeader header) {
        // alg 헤더를 그대로 신뢰하지 않고 RS256만 허용 (알고리즘 혼동 공격 방지)
        if (!"RS256".equals(header.getAlgorithm())) {
            throw new JwtException("unsupported algorithm: " + header.getAlgorithm());
        }

        String kid = header.getKeyId();
        if (kid == null || kid.isBlank()) {
            throw new JwtException("kid header is missing");
        }

        CachedJwks cached = jwksCache.get(jwksUri);

        // 캐시가 없거나 만료됐거나, 키 회전으로 kid가 캐시에 없으면 새로 받아온다.
        if (cached == null || cached.isExpired() || !cached.keysByKid().containsKey(kid)) {
            cached = fetchJwks(jwksUri);
            jwksCache.put(jwksUri, cached);
        }

        Key key = cached.keysByKid().get(kid);
        if (key == null) {
            throw new JwtException("unknown kid: " + kid);
        }
        return key;
    }

    // JWKS(공개키 목록)를 provider 엔드포인트에서 받아온다.
    //  - NIO Selector(loopback self-pipe)가 필요 없는 블로킹 방식(HttpURLConnection)을 사용한다.
    private CachedJwks fetchJwks(String jwksUri) {
        HttpURLConnection conn = null;
        try {
            conn = (HttpURLConnection) URI.create(jwksUri).toURL().openConnection();
            conn.setRequestMethod("GET");
            conn.setConnectTimeout(JWKS_HTTP_TIMEOUT_MS);
            conn.setReadTimeout(JWKS_HTTP_TIMEOUT_MS);

            String body;
            try (InputStream in = conn.getInputStream()) {
                body = new String(in.readAllBytes(), StandardCharsets.UTF_8);
            }

            JwkSet jwkSet = Jwks.setParser().build().parse(body);

            Map<String, Key> keysByKid = new HashMap<>();
            for (Jwk<?> jwk : jwkSet.getKeys()) {
                keysByKid.put(jwk.getId(), jwk.toKey());
            }

            return new CachedJwks(Map.copyOf(keysByKid), Instant.now());
        } catch (IOException e) {
            throw new JwtException("JWKS fetch failed: " + e.getMessage(), e);
        } finally {
            if (conn != null) {
                conn.disconnect();
            }
        }
    }

    private record CachedJwks(Map<String, Key> keysByKid, Instant fetchedAt) {
        boolean isExpired() {
            return fetchedAt.plus(JWKS_CACHE_TTL).isBefore(Instant.now());
        }
    }
}
