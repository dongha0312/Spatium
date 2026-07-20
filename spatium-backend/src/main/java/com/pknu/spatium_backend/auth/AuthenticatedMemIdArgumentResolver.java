package com.pknu.spatium_backend.auth;

import org.springframework.core.MethodParameter;
import org.springframework.security.authentication.AnonymousAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.support.WebDataBinderFactory;
import org.springframework.web.context.request.NativeWebRequest;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;
import org.springframework.web.method.support.ModelAndViewContainer;

import com.pknu.spatium_backend.exception.ApiException;

@Component
public class AuthenticatedMemIdArgumentResolver implements HandlerMethodArgumentResolver {

    @Override
    public boolean supportsParameter(MethodParameter parameter) {
        // @AuthenticatedMemId String memId 형태의 파라미터만 이 리졸버가 처리한다.
        return parameter.hasParameterAnnotation(AuthenticatedMemId.class)
                && String.class.equals(parameter.getParameterType());
    }

    @Override
    public Object resolveArgument(
            MethodParameter parameter,
            ModelAndViewContainer mavContainer,
            NativeWebRequest webRequest,
            WebDataBinderFactory binderFactory) {
        // 토큰 파싱/검증은 JwtAuthenticationFilter가 이미 수행했다.
        // 여기서는 SecurityContext에 저장된 인증 정보(principal = mem_id)만 꺼내온다.
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();

        if (authentication == null
                || !authentication.isAuthenticated()
                || authentication instanceof AnonymousAuthenticationToken) {
            throw new ApiException(401, "UNAUTHORIZED", "로그인이 필요합니다.");
        }

        String memId = String.valueOf(authentication.getPrincipal());
        if (memId.isBlank()) {
            throw new ApiException(401, "UNAUTHORIZED", "유효하지 않은 토큰입니다.");
        }

        return memId;
    }
}
