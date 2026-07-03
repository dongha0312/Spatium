package com.pknu.spatium_backend.auth;

import org.springframework.core.MethodParameter;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.support.WebDataBinderFactory;
import org.springframework.web.context.request.NativeWebRequest;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;
import org.springframework.web.method.support.ModelAndViewContainer;

import com.pknu.spatium_backend.exception.ApiException;
import com.pknu.spatium_backend.util.JwtUtil;

import lombok.RequiredArgsConstructor;

@Component
@RequiredArgsConstructor
public class AuthenticatedMemIdArgumentResolver implements HandlerMethodArgumentResolver {

    private final JwtUtil jwtUtil;

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
        // 컨트롤러마다 Authorization 헤더를 직접 파싱하지 않도록 여기서 한 번만 처리한다.
        String authorization = webRequest.getHeader("Authorization");
        if (authorization == null || !authorization.startsWith("Bearer ")) {
            throw new ApiException(401, "UNAUTHORIZED", "로그인이 필요합니다.");
        }

        String token = authorization.substring(7).trim();
        if (token.isEmpty()) {
            throw new ApiException(401, "UNAUTHORIZED", "유효하지 않은 토큰입니다.");
        }

        // JWT subject에는 Member.mem_id가 들어간다. 이 값만 컨트롤러에 주입한다.
        String memId = jwtUtil.validateAndGetMemId(token);
        if (memId == null || memId.isBlank()) {
            throw new ApiException(401, "UNAUTHORIZED", "유효하지 않은 토큰입니다.");
        }

        return memId;
    }
}
