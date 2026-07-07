import { springApi } from "../config/axiosInstance";
import { throwApiError, unwrapApiData } from "../utils/apiResponse";

export const postUserSignup = (memDTO) =>
  springApi.post("/api/users", memDTO).then(unwrapApiData).catch(throwApiError);

export const postLogin = ({ email, password }) =>
  springApi
    .post("/api/auth/sessions", { email, password })
    .then(unwrapApiData)
    .catch(throwApiError);

export const deleteLogout = () =>
  springApi
    .delete("/api/auth/sessions/current")
    .then(unwrapApiData)
    .catch(throwApiError);

export const getMyInfo = () =>
  springApi.get("/api/users/me").then(unwrapApiData).catch(throwApiError);

// 내 정보 수정 : 전달된 필드만 수정 (nickname/birthDate/password)
export const patchMyInfo = ({ nickname, birthDate, password } = {}) =>
  springApi
    .patch("/api/users/me", { nickname, birthDate, password })
    .then(unwrapApiData)
    .catch(throwApiError);

// 프로필 사진 변경 : multipart/form-data 로 image 파일 업로드
//  - axiosInstance가 FormData일 때 Content-Type을 자동 처리(boundary 설정)함
export const putMyAvatar = (file) => {
  const formData = new FormData();
  formData.append("image", file);
  return springApi
    .put("/api/users/me/avatar", formData)
    .then(unwrapApiData)
    .catch(throwApiError);
};

// 프로필 사진 삭제 : 저장된 이미지를 지우고 기본(이니셜) 상태로 되돌림 (204 No Content)
export const deleteMyAvatar = () =>
  springApi
    .delete("/api/users/me/avatar")
    .then(unwrapApiData)
    .catch(throwApiError);

// 회원 탈퇴 : 일반 회원은 { password }, 소셜 회원은 { idToken }으로 본인 재확인
export const deleteMyInfo = ({ password, idToken } = {}) =>
  springApi
    .delete("/api/users/me", { data: { password, idToken } })
    .then(unwrapApiData)
    .catch(throwApiError);

// 소셜 로그인 : provider가 발급한 ID Token만 보내고, sub/email은 백엔드가 직접 검증해서 얻음
export const postSocialLogin = ({ provider, idToken }) =>
  springApi
    .post("/api/auth/social-sessions", { provider, idToken })
    .then(unwrapApiData)
    .catch(throwApiError);

export const postSocialSignup = ({
  provider,
  idToken,
  nickname,
  birthDate,
  gender,
  termsAgreed,
  privacyAgreed,
}) =>
  springApi
    .post("/api/auth/social-users", {
      provider,
      idToken,
      nickname,
      birthDate,
      gender,
      termsAgreed,
      privacyAgreed,
    })
    .then(unwrapApiData)
    .catch(throwApiError);
