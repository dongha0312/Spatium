// 로그인 세션 저장소 (localStorage 기반)
//  - accessToken(수명 1시간)만 localStorage에 저장한다.
//  - refreshToken은 백엔드가 httpOnly 쿠키로 관리하므로 JS에서 저장/접근하지 않는다.
//    (XSS로 스크립트가 실행돼도 refreshToken은 탈취되지 않음)

const STORAGE_KEY = "spatium_auth";

// 이메일에서 닉네임을 유추 (@ 앞부분 사용, 없으면 "회원"으로 대체)
function deriveNickname(email) {
  const localPart = String(email || "").split("@")[0];
  return localPart || "회원";
}

// 로그인/회원가입 성공 시 세션 저장
//  - nickname을 직접 넘기면 그대로 사용하고(회원가입), 생략하면 이메일에서 유추함(로그인)
//  - provider : "LOCAL"(일반 가입) | "GOOGLE" 등 (소셜 가입은 비밀번호가 없어서 구분이 필요함)
//  - tokens : { accessToken } (refreshToken은 httpOnly 쿠키로 관리되므로 받지 않음)
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
  };
  localStorage.setItem(STORAGE_KEY, JSON.stringify(session));
  return session;
}

// 저장된 accessToken 조회 (없으면 null) : 로그아웃 등 인증 API 호출 시 사용
export function getAccessToken() {
  return getLoginSession()?.accessToken || null;
}

// 토큰 재발급 성공 시 세션의 accessToken만 갱신 (이메일/닉네임 등은 유지)
//  - 새 refreshToken은 재발급 응답의 Set-Cookie로 브라우저가 알아서 갱신함
export function updateTokens({ accessToken }) {
  const session = getLoginSession();
  if (!session) return null;

  session.accessToken = accessToken || session.accessToken;
  localStorage.setItem(STORAGE_KEY, JSON.stringify(session));
  return session;
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
//  - refreshToken 쿠키는 로그아웃 API 응답(Set-Cookie 만료)으로 서버가 삭제함
export function clearLoginSession() {
  localStorage.removeItem(STORAGE_KEY);
}
