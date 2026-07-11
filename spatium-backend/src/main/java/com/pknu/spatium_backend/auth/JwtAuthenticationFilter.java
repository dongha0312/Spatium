package com.pknu.spatium_backend.auth;

import java.io.IOException;
import java.util.List;

import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import com.pknu.spatium_backend.repository.MemberRepository;
import com.pknu.spatium_backend.util.JwtUtil;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;

// Authorization: Bearer <accessToken> 헤더를 검증해서
// SecurityContextHolder에 인증 정보(principal = mem_id)를 저장하는 필터.
//  - 토큰이 없거나 유효하지 않으면 인증 정보를 저장하지 않고 그냥 통과시킨다.
//    (인증 필요 여부 판단과 401 응답은 SecurityConfig의 인가 규칙/EntryPoint가 담당)
@Component
@RequiredArgsConstructor
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private static final String BEARER_PREFIX = "Bearer ";

    private final JwtUtil jwtUtil;

    private final MemberRepository memberRepository;

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {

        String authorization = request.getHeader("Authorization");

        if (authorization != null && authorization.startsWith(BEARER_PREFIX)) {
            String token = authorization.substring(BEARER_PREFIX.length()).trim();

            if (!token.isEmpty()) {
                // JWT subject에는 Member.mem_id가 들어간다. (JwtUtil 참고)
                // type=access인 토큰만 인증에 사용 가능 (refreshToken으로 API 호출 차단)
                String memId = jwtUtil.validateAccessTokenAndGetMemId(token);

                // 토큰이 유효해도 mem_id가 실존 회원이어야 인증 인정
                //  - 탈퇴한 회원의 만료 전 토큰으로 API를 쓰는 것을 차단
                if (memId != null && !memId.isBlank() && memberRepository.existsById(memId)) {
                    UsernamePasswordAuthenticationToken authentication =
                            new UsernamePasswordAuthenticationToken(memId, null, List.of());
                    authentication.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));
                    SecurityContextHolder.getContext().setAuthentication(authentication);
                }
            }
        }

        filterChain.doFilter(request, response);
    }
}
