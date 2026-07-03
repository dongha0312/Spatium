package com.pknu.spatium_backend.auth;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

@Target(ElementType.PARAMETER)
@Retention(RetentionPolicy.RUNTIME)
// 인증이 필요한 컨트롤러 메서드에서 현재 로그인한 회원 ID를 받기 위한 표시용 어노테이션.
// 실제 JWT 파싱/검증은 AuthenticatedMemIdArgumentResolver가 담당한다.
public @interface AuthenticatedMemId {
}
