package com.pknu.spatium_backend.controller;

import java.util.List;
import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.pknu.spatium_backend.auth.AuthenticatedMemId;
import com.pknu.spatium_backend.dto.PageResponseDTO;
import com.pknu.spatium_backend.dto.ProjectDTO.ResponseProjectCreateDTO;
import com.pknu.spatium_backend.dto.ProjectDTO.ResponseProjectListDTO;
import com.pknu.spatium_backend.exception.ApiException;
import com.pknu.spatium_backend.service.ProjectService;

import lombok.RequiredArgsConstructor;

@RestController
@RequiredArgsConstructor
@RequestMapping(path = "/api/projects")
public class ProjectController {

    private final ProjectService projectService;

    @GetMapping
    public ResponseEntity<?> getProjectList(
            @AuthenticatedMemId String memId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        List<ResponseProjectListDTO> items = projectService.getProjectList(memId);
        PageResponseDTO<ResponseProjectListDTO> data = new PageResponseDTO<>(
                items,
                page,
                size,
                items.size(),
                items.isEmpty() ? 0 : 1,
                false);

        return ResponseEntity.ok(Map.of(
                "statusCode", 200,
                "message", "프로젝트 목록 조회에 성공했습니다.",
                "data", data));
    }

    @PostMapping
    public ResponseEntity<?> createProject(
            @AuthenticatedMemId String memId,
            @RequestBody Map<String, String> requestBody) {
        String projectName = requestBody.get("projectName");
        if (projectName == null || projectName.trim().isEmpty()) {
            throw new ApiException(400, "INVALID_PROJECT_NAME", "프로젝트 이름이 올바르지 않습니다.");
        }

        ResponseProjectCreateDTO data = projectService.createProject(projectName.trim(), memId);
        return ResponseEntity.status(201).body(Map.of(
                "statusCode", 201,
                "message", "프로젝트가 생성되었습니다.",
                "data", data));
    }

    @GetMapping(path = "/{projectId}")
    public ResponseEntity<?> getProject(
            @AuthenticatedMemId String memId,
            @PathVariable String projectId) {
        return ResponseEntity.ok(Map.of(
                "statusCode", 200,
                "message", "프로젝트 상세 조회에 성공했습니다.",
                "data", projectService.getProject(memId, projectId)));
    }

    @DeleteMapping
    public ResponseEntity<?> deleteProject(
            @AuthenticatedMemId String memId,
            @RequestBody Map<String, String> requestBody) {
        String projectId = requestBody.get("projectId");
        if (projectId == null || projectId.trim().isEmpty()) {
            throw new ApiException(400, "INVALID_REQUEST", "요청 값이 올바르지 않습니다.");
        }

        projectService.deleteProject(memId, projectId.trim());
        return ResponseEntity.ok(Map.of(
                "statusCode", 200,
                "message", "프로젝트 삭제에 성공했습니다.",
                "data", projectId.trim()));
    }
}
