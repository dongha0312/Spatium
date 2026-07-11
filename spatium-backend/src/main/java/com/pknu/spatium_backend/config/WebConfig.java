package com.pknu.spatium_backend.config;

import java.util.List;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import com.pknu.spatium_backend.auth.AuthenticatedMemIdArgumentResolver;

import lombok.RequiredArgsConstructor;

@Configuration
@RequiredArgsConstructor
public class WebConfig implements WebMvcConfigurer {

    private final AuthenticatedMemIdArgumentResolver authenticatedMemIdArgumentResolver;

    @Override
    public void addArgumentResolvers(List<HandlerMethodArgumentResolver> resolvers) {
        // @AuthenticatedMemId 파라미터가 JWT 검증 결과를 받을 수 있도록 Spring MVC에 등록한다.
        resolvers.add(authenticatedMemIdArgumentResolver);
    }
}
