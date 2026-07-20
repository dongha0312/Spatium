import { springApi } from "../config/axiosInstance";
import { throwApiError, unwrapApiData } from "../utils/apiResponse";

export const getProjectList = (params = {}) =>
  springApi.get("/api/projects", { params }).then(unwrapApiData).catch(throwApiError);

export const postProject = (projectName) =>
  springApi
    .post("/api/projects", { projectName })
    .then(unwrapApiData)
    .catch(throwApiError);

export const getProjectInfo = (projectId) =>
  springApi
    .get(`/api/projects/${projectId}`)
    .then(unwrapApiData)
    .catch(throwApiError);

export const patchProject = ({ projectId, projectName }) =>
  springApi
    .patch(`/api/projects/${projectId}`, { projectName })
    .then(unwrapApiData)
    .catch(throwApiError);

export const deleteProject = ({ projectId }) =>
  springApi
    .delete("/api/projects", {
      data: {
        projectId,
      },
    })
    .then(unwrapApiData)
    .catch(throwApiError);
