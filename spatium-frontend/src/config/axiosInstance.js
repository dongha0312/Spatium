/**
 * 어떤 백엔드 서버와 통신을 할 것인지를 정의해 놓는 페이지
 *  - 백엔드 서버가 여러개면 모두 이곳에 정의함
 *  - 사용 라이브러리 : axios 라이브러리 import 해야함
 * 
 * (중요) 이 파일이 작동하려면, src/setupProxy.js 파일이 있어야함
 *  - 꼭, src 폴더 밑에 파일이 위치해야 하며,
 *    파일명은 수정 불가(고정된 이름임)
 *  - React 서버 실행 시 자동으로 실행되는 파일임
 *  - 프록시 설정 만들어야 사용 가능(서버에서 실행시켜 놓을 수 있음)
 */
// axios 라이브러리 불러들이기
import axios from "axios";
import {
  clearLoginSession,
  getAccessToken,
  updateTokens,
} from "../utils/authSession";

/** SpringBoot 백엔드 서버 통신 설정 */
export const springApi = axios.create({
    // 프록시 서버에서 사용할 대표 URL 정의(이니셜)
    //  - 해당 이름은 프록시서버 설정 파일에서 구분자로 사용되는 이름임
    //  - 최초 사용자가 요청한 URL : http://localhost:3000/react/springboot_test
    //  - baseURL로 변경됨 : http://localhost:3000/spring/react/springboot_test
    baseURL: "",

    // HTTP 통신을 위한 헤더 전송정보 정의
    headers: {
        // json 형태의 데이터로 전송하겠다는 규칙 정의
        //  - 백엔드 서버에서도 json으로 응답을 해야함
        "Content-Type" : "application/json"
    },
});

springApi.interceptors.request.use((config) => {
    const accessToken = getAccessToken();

    config.headers = config.headers || {};

    if (config.data instanceof FormData) {
        delete config.headers["Content-Type"];
        delete config.headers["content-type"];
    }

    if (accessToken) {
        config.headers.Authorization = `Bearer ${accessToken}`;
    }

    return config;
});

// 토큰 재발급 (POST /api/auth/token)
//  - springApi가 아닌 순수 axios를 사용 : 인터셉터 재귀 호출 방지
//  - 동시에 여러 요청이 401을 받아도 재발급은 1번만 수행 (refreshPromise 공유)
//  - refreshToken은 httpOnly 쿠키에 있어서 JS가 읽을 수 없고,
//    같은 출처(proxy 경유) 요청이라 브라우저가 쿠키를 자동으로 실어 보낸다.
//    새 refreshToken도 응답의 Set-Cookie로 자동 갱신된다.
let refreshPromise = null;

const reissueTokens = async () => {
    const res = await axios.post("/api/auth/token");
    const data = res.data?.data;

    updateTokens({
        accessToken: data?.accessToken,
    });

    return data?.accessToken;
};

springApi.interceptors.response.use(
    (response) => response,
    async (error) => {
        const status = error.response?.data?.statusCode || error.response?.status;
        const requestUrl = error.config?.url || "";
        const isAuthRequest =
            requestUrl.includes("/api/auth/sessions") ||
            requestUrl.includes("/api/auth/social-sessions") ||
            requestUrl.includes("/api/auth/token");

        // accessToken 만료(401) 시 : refreshToken으로 자동 재발급 후 원래 요청 1회 재시도
        if (status === 401 && !isAuthRequest && !error.config._retried) {
            try {
                refreshPromise = refreshPromise || reissueTokens();
                const newAccessToken = await refreshPromise;
                refreshPromise = null;

                error.config._retried = true;
                error.config.headers = error.config.headers || {};
                error.config.headers.Authorization = `Bearer ${newAccessToken}`;
                return springApi(error.config);
            } catch (refreshError) {
                // 재발급 실패(refreshToken 만료/폐기) : 세션 정리 후 로그인 페이지로
                refreshPromise = null;
                clearLoginSession();
                if (window.location.pathname !== "/auth/login") {
                    window.location.assign("/auth/login");
                }
                return Promise.reject(error);
            }
        }

        // 재시도까지 실패한 401 : 세션 정리 후 로그인 페이지로
        if (status === 401 && !isAuthRequest) {
            clearLoginSession();
            if (window.location.pathname !== "/auth/login") {
                window.location.assign("/auth/login");
            }
        }

        return Promise.reject(error);
    },
);

