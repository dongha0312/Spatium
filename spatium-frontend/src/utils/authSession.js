// 데모용 로그인 세션 저장소
//  - 아직 백엔드 로그인 연동 전이라, 브라우저 localStorage로 로그인 상태를 흉내냄
//  - 추후 백엔드 연동 시 이 파일의 내용을 실제 인증 토큰/세션 처리로 교체하면 됨

const STORAGE_KEY = "spatium_auth";

// 이메일에서 닉네임을 유추 (@ 앞부분 사용, 없으면 "회원"으로 대체)
function deriveNickname(email) {
    const localPart = String(email || "").split("@")[0];
    return localPart || "회원";
}

// 로그인/회원가입 성공 시 세션 저장
//  - nickname을 직접 넘기면 그대로 사용하고(회원가입), 생략하면 이메일에서 유추함(로그인)
//  - provider : "LOCAL"(일반 가입) | "GOOGLE" 등 (소셜 가입은 비밀번호가 없어서 구분이 필요함)
export function saveLoginSession(email, nickname, provider = "LOCAL") {
    const session = { email, nickname: nickname || deriveNickname(email), provider };
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
export function clearLoginSession() {
    localStorage.removeItem(STORAGE_KEY);
}
