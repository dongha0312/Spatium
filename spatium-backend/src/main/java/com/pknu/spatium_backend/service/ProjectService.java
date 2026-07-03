package com.pknu.spatium_backend.service;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Stream;

import org.springframework.stereotype.Service;

import com.pknu.spatium_backend.dto.ProjectDTO.ResponseProjectCreateDTO;
import com.pknu.spatium_backend.dto.ProjectDTO.ResponseProjectListDTO;
import com.pknu.spatium_backend.exception.ApiException;
import com.pknu.spatium_backend.model.Project;
import com.pknu.spatium_backend.repository.ProjectRepository;
import com.pknu.spatium_backend.repository.RoomRepository;

import jakarta.transaction.Transactional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@Service
@Slf4j
@RequiredArgsConstructor
public class ProjectService {

    private final ProjectRepository projectRepository;
    private final RoomRepository roomRepository;

    public List<ResponseProjectListDTO> getProjectList(String memId) {
        return projectRepository.getProjectList(memId).stream()
                .map(project -> new ResponseProjectListDTO(
                        project.getProj_code(),
                        project.getProj_name(),
                        roomRepository.countByRoomProj(project.getProj_code()),
                        0))
                .toList();
    }

    @Transactional
    public ResponseProjectCreateDTO createProject(String projectName, String memId) {
        // proj_mem에는 JWT에서 검증된 내부 회원 ID를 저장한다.
        // 이후 프로젝트/룸/파일 경로는 이 memId를 기준으로 소유권을 판단한다.
        Project project = Project.builder()
                .proj_code(UUID.randomUUID().toString().substring(0, 30))
                .proj_mem(memId)
                .proj_name(projectName)
                .build();

        Project savedProject = projectRepository.save(project);
        return new ResponseProjectCreateDTO(
                savedProject.getProj_code(),
                savedProject.getProj_name());
    }

    public Map<String, Object> getProject(String memId, String projectId) {
        Project project = getOwnedProject(memId, projectId);
        Path projectDir = dataRoot()
                .resolve(project.getProj_mem())
                .resolve(project.getProj_code())
                .toAbsolutePath()
                .normalize();

        return Map.of(
                "projectName", project.getProj_name(),
                "projectPath", projectDir.toString());
    }

    @Transactional
    public void deleteProject(String memId, String projectId) {
        Project project = getOwnedProject(memId, projectId);
        Path projectDir = dataRoot()
                .resolve(project.getProj_mem())
                .resolve(project.getProj_code())
                .toAbsolutePath()
                .normalize();

        roomRepository.deleteByRoomProj(projectId);
        projectRepository.delete(project);
        projectRepository.flush();
        deleteDirectory(projectDir);
    }

    public Project getOwnedProject(String memId, String projectId) {
        Project project = projectRepository.findById(projectId)
                .orElseThrow(() -> new ApiException(404, "PROJECT_NOT_FOUND", "프로젝트를 찾을 수 없습니다."));

        // 요청자가 이 프로젝트의 소유자인지 모든 프로젝트 API의 공통 기준으로 확인한다.
        if (!memId.equals(project.getProj_mem())) {
            throw new ApiException(403, "FORBIDDEN", "해당 프로젝트에 접근할 권한이 없습니다.");
        }

        return project;
    }

    private Path dataRoot() {
        // ProjectService와 RoomService가 같은 data 루트를 기준으로 파일 경로를 계산한다.
        return Paths.get(System.getProperty("user.dir"), "data")
                .toAbsolutePath()
                .normalize();
    }

    private void deleteDirectory(Path targetDir) {
        Path dataRoot = dataRoot();
        Path normalizedTargetDir = targetDir.toAbsolutePath().normalize();

        // 프로젝트 삭제 시 data 루트 밖의 파일이 지워지지 않도록 한 번 더 확인한다.
        if (!normalizedTargetDir.startsWith(dataRoot)) {
            throw new ApiException(400, "INVALID_REQUEST", "삭제할 수 없는 경로입니다.");
        }

        if (!Files.exists(normalizedTargetDir)) {
            log.info("Project directory does not exist. path={}", normalizedTargetDir);
            return;
        }

        try (Stream<Path> paths = Files.walk(normalizedTargetDir)) {
            paths.sorted(Comparator.reverseOrder())
                    .forEach(path -> {
                        try {
                            Files.deleteIfExists(path);
                        } catch (IOException e) {
                            throw new IllegalStateException("프로젝트 폴더 삭제 중 오류가 발생했습니다.", e);
                        }
                    });
        } catch (IOException e) {
            throw new IllegalStateException("프로젝트 폴더 삭제 중 오류가 발생했습니다.", e);
        }
    }
}
