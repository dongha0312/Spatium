package com.pknu.spatium_backend.service;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.stereotype.Service;

import com.pknu.spatium_backend.dto.ProjectDTO.ResponseProjectCreateDTO;
import com.pknu.spatium_backend.dto.ProjectDTO.ResponseProjectListDTO;
import com.pknu.spatium_backend.exception.ApiException;
import com.pknu.spatium_backend.model.Project;
import com.pknu.spatium_backend.model.Room;
import com.pknu.spatium_backend.repository.ProjectRepository;
import com.pknu.spatium_backend.repository.RoomRepository;
import com.pknu.spatium_backend.storage.FileStorageCleanup;

import jakarta.transaction.Transactional;
import lombok.RequiredArgsConstructor;

@Service
@RequiredArgsConstructor
public class ProjectService {

    private final ProjectRepository projectRepository;
    private final RoomRepository roomRepository;
    private final FileStorageCleanup fileStorageCleanup;

    public List<ResponseProjectListDTO> getProjectList(String memId) {
        return projectRepository.findProjectSummaries(memId).stream()
                .map(project -> new ResponseProjectListDTO(
                        project.getProjectId(),
                        project.getProjectName(),
                        project.getRoomCount().intValue(),
                        0,
                        project.getCreatedAt() != null ? project.getCreatedAt().toString() : null))
                .toList();
    }

    @Transactional
    public ResponseProjectCreateDTO createProject(String projectName, String memId) {
        Project project = Project.builder()
                .proj_code(UUID.randomUUID().toString().substring(0, 30))
                .proj_mem(memId)
                .proj_name(projectName)
                .build();
        Project savedProject = projectRepository.save(project);
        return new ResponseProjectCreateDTO(savedProject.getProj_code(), savedProject.getProj_name());
    }

    @Transactional
    public void renameProject(String memId, String projectId, String projectName) {
        if (projectName == null || projectName.isBlank()) {
            throw new ApiException(400, "INVALID_PROJECT_NAME", "프로젝트 이름이 올바르지 않습니다.");
        }
        Project project = getOwnedProject(memId, projectId);
        project.setProj_name(projectName.trim());
        projectRepository.save(project);
    }

    public Map<String, Object> getProject(String memId, String projectId) {
        Project project = getOwnedProject(memId, projectId);
        return Map.of("projectId", project.getProj_code(), "projectName", project.getProj_name());
    }

    @Transactional
    public void deleteAllByMember(String memId) {
        List<Project> projects = projectRepository.getProjectList(memId);
        List<String> objectKeys = new ArrayList<>();

        for (Project project : projects) {
            List<Room> rooms = roomRepository.findByRoomProj(project.getProj_code());
            rooms.stream()
                    .map(Room::getRoom_path)
                    .filter(path -> path != null && !path.isBlank())
                    .forEach(path -> objectKeys.addAll(RoomService.roomObjectKeys(path)));
            roomRepository.deleteByRoomProj(project.getProj_code());
        }

        projectRepository.deleteAll(projects);
        projectRepository.flush();
        fileStorageCleanup.deleteAfterCommit(objectKeys);
    }

    @Transactional
    public void deleteProject(String memId, String projectId) {
        Project project = getOwnedProject(memId, projectId);
        List<String> objectKeys = roomRepository.findByRoomProj(projectId).stream()
                .map(Room::getRoom_path)
                .filter(path -> path != null && !path.isBlank())
                .flatMap(path -> RoomService.roomObjectKeys(path).stream())
                .toList();

        roomRepository.deleteByRoomProj(projectId);
        projectRepository.delete(project);
        projectRepository.flush();
        fileStorageCleanup.deleteAfterCommit(objectKeys);
    }

    public Project getOwnedProject(String memId, String projectId) {
        Project project = projectRepository.findById(projectId)
                .orElseThrow(() -> new ApiException(404, "PROJECT_NOT_FOUND", "프로젝트를 찾을 수 없습니다."));
        if (!memId.equals(project.getProj_mem())) {
            throw new ApiException(403, "FORBIDDEN", "해당 프로젝트에 접근할 권한이 없습니다.");
        }
        return project;
    }
}
