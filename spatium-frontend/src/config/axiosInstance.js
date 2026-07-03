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
import { clearLoginSession, getAccessToken } from "../utils/authSession";

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

    if (accessToken) {
        config.headers = config.headers || {};
        config.headers.Authorization = `Bearer ${accessToken}`;
    }

    return config;
});

springApi.interceptors.response.use(
    (response) => response,
    (error) => {
        const status = error.response?.data?.statusCode || error.response?.status;
        const requestUrl = error.config?.url || "";
        const isLoginRequest =
            requestUrl.includes("/api/auth/sessions") ||
            requestUrl.includes("/api/auth/social-sessions");

        if (status === 401 && !isLoginRequest) {
            clearLoginSession();
            if (window.location.pathname !== "/auth/login") {
                window.location.assign("/auth/login");
            }
        }

        return Promise.reject(error);
    },
);

