package com.pknu.spatium_backend.config;

import java.io.IOException;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

import com.pknu.spatium_backend.auth.JwtAuthenticationFilter;

import jakarta.servlet.DispatcherType;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;

@Configuration
@EnableWebSecurity
@RequiredArgsConstructor
public class SecurityConfig {

    private final JwtAuthenticationFilter jwtAuthenticationFilter;

    // GlobalExceptionHandler의 ApiException(401) 응답과 동일한 형식
    //  - {statusCode, code, message, errors}
    //  - 고정 값이므로 ObjectMapper 없이 리터럴로 유지 (Boot 4에서는
    //    jackson-databind가 컴파일 클래스패스에 노출되지 않음)
    private static final String UNAUTHORIZED_BODY =
            "{\"statusCode\":401,\"code\":\"UNAUTHORIZED\",\"message\":\"로그인이 필요합니다.\",\"errors\":[]}";

    // 비밀번호 해시용 인코더 (BCrypt)
    //  - 회원가입 : encode()로 해시 저장, 로그인/탈퇴 : matches()로 비교
    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
                // JWT stateless 인증이므로 세션/CSRF/폼로그인은 모두 사용하지 않는다.
                .csrf(AbstractHttpConfigurer::disable)
                .formLogin(AbstractHttpConfigurer::disable)
                .httpBasic(AbstractHttpConfigurer::disable)
                .sessionManagement(session -> session
                        .sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth
                        // 에러 디스패치(/error 내부 포워딩)는 인증 없이 통과
                        //  - 없으면 404/500이 전부 401 UNAUTHORIZED로 둔갑함
                        .dispatcherTypeMatchers(DispatcherType.ERROR).permitAll()
                        // CORS preflight는 인증 없이 통과
                        .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                        // 회원가입
                        .requestMatchers(HttpMethod.POST, "/api/users").permitAll()
                        // 로그인
                        .requestMatchers(HttpMethod.POST, "/api/auth/sessions").permitAll()
                        // 소셜 로그인/가입 (social-sessions, social-users)
                        .requestMatchers("/api/auth/social-*").permitAll()
                        // 토큰 재발급 (accessToken 만료 상태에서 호출되므로 인증 불필요,
                        //  refreshToken 자체 검증은 MemberService.reissueTokens가 수행)
                        .requestMatchers(HttpMethod.POST, "/api/auth/token").permitAll()
                        // 그 외 전부 인증 필요
                        .anyRequest().authenticated())
                // 미인증 요청의 401 응답을 기존 공통 에러 스펙으로 내려준다.
                .exceptionHandling(exception -> exception
                        .authenticationEntryPoint(this::writeUnauthorizedResponse))
                // Bearer 토큰 검증 필터 등록
                .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }

    private void writeUnauthorizedResponse(
            HttpServletRequest request,
            HttpServletResponse response,
            AuthenticationException authException) throws IOException {

        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding("UTF-8");
        response.getWriter().write(UNAUTHORIZED_BODY);
    }
}
