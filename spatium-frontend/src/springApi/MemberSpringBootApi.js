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

export const postSocialLogin = ({ provider, providerUserId, email }) =>
  springApi
    .post("/api/auth/social-sessions", { provider, providerUserId, email })
    .then(unwrapApiData)
    .catch(throwApiError);

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
    .then(unwrapApiData)
    .catch(throwApiError);
