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

export const deleteMyInfo = () =>
  springApi.delete("/api/users/me").then(unwrapApiData).catch(throwApiError);

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
