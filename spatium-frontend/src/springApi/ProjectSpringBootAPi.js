import { springApi } from "../config/axiosInstance";

// 프로젝트 목록 조회
export const getProjectList = () => {
    return springApi.get("/api/projects")
}

// 새 프로젝트 생성
export const postProject = () => {
    return springApi.post("/api/projects")
}

// 프로젝트 상세 조회
export const  getProjectInfo= (project) => {
    return springApi.get(`/api/projects/${project}`)
}