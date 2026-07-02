// axiosInstance.js 불러들이기
//  - springApi 변수 사용
import { springApi } from "../config/axiosInstance";

// 공통 에러 처리 : 메시지 + HTTP 상태코드 + 에러코드를 담은 Error 객체를 만들어서 throw
//  - err.status로 404(미가입), 409(중복) 등을 구분
//  - err.code로 "DUPLICATED_EMAIL", "SOCIAL_USER_ALREADY_EXISTS" 등 세부 코드 구분
const throwApiError = (error) => {
  const responseData = error.response?.data;
  const message =
    typeof responseData === "string"
      ? responseData
      : responseData?.message || error.message;

  const apiError = new Error(message);
  apiError.status = error.response?.status;
  apiError.code = responseData?.code;
  throw apiError;
};

// 일반 회원가입 (POST /api/users)
//  - memDTO : { email, nickname, password, birthDate, gender, termsAgreed, privacyAgreed }
export const postUserSignup = (memDTO) =>
  springApi
    .post("/api/users", memDTO)
    .then((response) => response.data)
    .catch(throwApiError);

// 소셜 로그인 (POST /api/auth/social-sessions)
//  - 성공 시 기존 회원 정보 반환, 미가입 회원이면 404 에러 발생 (err.status === 404로 구분)
export const postSocialLogin = ({ provider, providerUserId, email }) =>
  springApi
    .post("/api/auth/social-sessions", { provider, providerUserId, email })
    .then((response) => response.data)
    .catch(throwApiError);

// 소셜 회원가입 (POST /api/auth/social-users)
export const postSocialSignup = ({
  provider,
  providerUserId,
  email,
  nickname,
  birthDate,
  gender,
  termsAgreed,
  privacyAgreed,
}) =>
  springApi
    .post("/api/auth/social-users", {
      provider,
      providerUserId,
      email,
      nickname,
      birthDate,
      gender,
      termsAgreed,
      privacyAgreed,
    })
    .then((response) => response.data)
    .catch(throwApiError);
