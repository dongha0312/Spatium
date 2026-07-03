package com.pknu.spatium_backend.controller;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.pknu.spatium_backend.dto.ErrorResponseDTO;
import com.pknu.spatium_backend.dto.ErrorResponseDTO.FieldErrorDTO;
import com.pknu.spatium_backend.dto.ProjectDTO.ResponseProjectCreateDTO;
import com.pknu.spatium_backend.dto.ProjectDTO.ResponseProjectListDTO;
import com.pknu.spatium_backend.dto.ResponseDTO;
import com.pknu.spatium_backend.service.ProjectService;

import lombok.RequiredArgsConstructor;


@RestController
@RequiredArgsConstructor
@RequestMapping(path = "/api/projects")
public class ProjectController {

    private final ProjectService projectService;

    // 프로젝트 전체 목록 조회 -> 지금은 편의상 post 매핑으로 사용함.
    @PostMapping(path = "/list")
    public ResponseEntity<?> getProjectList(@RequestBody Map<String, String> requestBody) {
        String memId = requestBody.get("memId");

        if (memId == null || memId.trim().isEmpty()) {
            Map<String, Object> errorBody = new HashMap<>();
            errorBody.put("statusCode", 400);
            errorBody.put("message", "회원 ID가 필요합니다.");
            errorBody.put("data", null);

            return ResponseEntity.badRequest().body(errorBody);
        }

        try {
            List<ResponseProjectListDTO> resProjectList = this.projectService.getProjectList(memId.trim());

            ResponseDTO<List<ResponseProjectListDTO>> responseDTO = new ResponseDTO<>();
            responseDTO.setStatusCode(200);
            responseDTO.setMessage("프로젝트 목록 조회에 성공했습니다.");
            responseDTO.setData(resProjectList);

            return ResponseEntity.ok(responseDTO);
        } catch (IllegalArgumentException e) {
            ResponseDTO<Object> errorResponseDTO = new ResponseDTO<>();
            errorResponseDTO.setStatusCode(404);
            errorResponseDTO.setMessage(e.getMessage());
            errorResponseDTO.setData(null);

            return ResponseEntity.status(404).body(errorResponseDTO);
        }
    }

    // 프로젝트 생성
    @PostMapping(path = "")
    public ResponseEntity<?> createProject(@RequestBody Map<String, String> requestBody) {
        String projectName = requestBody.get("projectName");
        String projectMem = requestBody.get("projectMem");

        if (projectName == null || projectName.trim().isEmpty()) {
            ResponseDTO<Object> errorResponseDTO = new ResponseDTO<>();
            errorResponseDTO.setStatusCode(400);
            errorResponseDTO.setMessage("프로젝트 이름이 필요합니다.");
            errorResponseDTO.setData(null);

            return ResponseEntity.badRequest().body(errorResponseDTO);
        }

        if (projectMem == null || projectMem.trim().isEmpty()) {
            ResponseDTO<Object> errorResponseDTO = new ResponseDTO<>();
            errorResponseDTO.setStatusCode(400);
            errorResponseDTO.setMessage("회원 ID가 필요합니다.");
            errorResponseDTO.setData(null);

            return ResponseEntity.badRequest().body(errorResponseDTO);
        }

        ResponseProjectCreateDTO resProject = this.projectService.createProject(projectName.trim(), projectMem.trim());

        ResponseDTO<ResponseProjectCreateDTO> responseDTO = new ResponseDTO<>();
        responseDTO.setStatusCode(201);
        responseDTO.setMessage("프로젝트 생성에 성공했습니다.");
        responseDTO.setData(resProject);

        return ResponseEntity.status(201).body(responseDTO);
    }

    @DeleteMapping(path = "")
    public ResponseEntity<?> deleteProject(@RequestBody Map<String, String> requestBody) {
        String projectId = requestBody.get("projectId");

        if (projectId == null || projectId.trim().isEmpty()) {
            ErrorResponseDTO errorResponseDTO = new ErrorResponseDTO(
                    400,
                    "INVALID_REQUEST",
                    "요청 값이 올바르지 않습니다.",
                    List.of(new FieldErrorDTO("projectId", "프로젝트 ID가 필요합니다."))
            );

            return ResponseEntity.badRequest().body(errorResponseDTO);
        }

        try {
            projectService.deleteProject(projectId.trim());

            ResponseDTO<String> responseDTO = new ResponseDTO<>();
            responseDTO.setStatusCode(200);
            responseDTO.setMessage("프로젝트 삭제에 성공했습니다.");
            responseDTO.setData(projectId.trim());

            return ResponseEntity.ok(responseDTO);
        } catch (IllegalArgumentException e) {
            ErrorResponseDTO errorResponseDTO = new ErrorResponseDTO(
                    404,
                    "PROJECT_NOT_FOUND",
                    e.getMessage(),
                    List.of(new FieldErrorDTO("projectId", "존재하지 않는 프로젝트 ID입니다."))
            );

            return ResponseEntity.status(404).body(errorResponseDTO);
        } catch (IllegalStateException e) {
            ErrorResponseDTO errorResponseDTO = new ErrorResponseDTO(
                    500,
                    "PROJECT_DELETE_FAILED",
                    e.getMessage(),
                    List.of(new FieldErrorDTO("projectId", "프로젝트 폴더 삭제 중 오류가 발생했습니다."))
            );

            return ResponseEntity.status(500).body(errorResponseDTO);
        }
    }
    
}
