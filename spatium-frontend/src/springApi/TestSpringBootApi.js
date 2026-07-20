// axiosInstance.js 불러들이기
//  - springApi 변수 사용
import {springApi} from "../config/axiosInstance";

// 회원 상세 조회를 위한 백엔드 URL 패턴 정의 및 전송방식 함수 정의
export const getTestData = () => 
    springApi.get("/test/read")