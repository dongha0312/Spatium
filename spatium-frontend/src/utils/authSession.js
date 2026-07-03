// 로그인 세션 저장소 (localStorage 기반)
//  - 백엔드 로그인(JWT) 연동 완료 : accessToken/refreshToken도 함께 저장함
//  - 인증이 필요한 API 호출 시 getAccessToken()으로 토큰을 꺼내 Authorization 헤더에 사용

const STORAGE_KEY = "spatium_auth";

// 이메일에서 닉네임을 유추 (@ 앞부분 사용, 없으면 "회원"으로 대체)
function deriveNickname(email) {
  const localPart = String(email || "").split("@")[0];
  return localPart || "회원";
}

// 로그인/회원가입 성공 시 세션 저장
//  - nickname을 직접 넘기면 그대로 사용하고(회원가입), 생략하면 이메일에서 유추함(로그인)
//  - provider : "LOCAL"(일반 가입) | "GOOGLE" 등 (소셜 가입은 비밀번호가 없어서 구분이 필요함)
//  - tokens : { accessToken, refreshToken } (백엔드 로그인 응답의 토큰, 없으면 생략 가능)
export function saveLoginSession(
  email,
  nickname,
  provider = "LOCAL",
  tokens = {},
) {
  const session = {
    email,
    nickname: nickname || deriveNickname(email),
    provider,
    accessToken: tokens.accessToken || null,
    refreshToken: tokens.refreshToken || null,
  };
  localStorage.setItem(STORAGE_KEY, JSON.stringify(session));
  return session;
}

// 저장된 accessToken 조회 (없으면 null) : 로그아웃 등 인증 API 호출 시 사용
export function getAccessToken() {
  return getLoginSession()?.accessToken || null;
}

// 현재 로그인 세션 조회 (없으면 null)
export function getLoginSession() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

// 로그아웃 : 세션 삭제
export function clearLoginSession() {
  localStorage.removeItem(STORAGE_KEY);
}
