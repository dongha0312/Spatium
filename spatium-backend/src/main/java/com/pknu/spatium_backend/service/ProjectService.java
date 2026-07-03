package com.pknu.spatium_backend.service;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;
import java.util.stream.Stream;

import org.springframework.stereotype.Service;

import com.pknu.spatium_backend.dto.ProjectDTO.ResponseProjectCreateDTO;
import com.pknu.spatium_backend.dto.ProjectDTO.ResponseProjectListDTO;
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

    public List<ResponseProjectListDTO> getProjectList(String memID) {
        List<Project> projects = projectRepository.getProjectList(memID);

        return projects.stream()
                .map(project -> new ResponseProjectListDTO(
                        project.getProj_code(),
                        project.getProj_name(),
                        0,
                        0
                ))
                .toList();
    }

    @Transactional
    public ResponseProjectCreateDTO createProject(String projectName, String projectMem) {
        Project project = Project.builder()
                .proj_code(UUID.randomUUID().toString().substring(0, 30))
                .proj_mem(projectMem)
                .proj_name(projectName)
                .build();

        Project savedProject = projectRepository.save(project);

        return new ResponseProjectCreateDTO(
                savedProject.getProj_code(),
                savedProject.getProj_name()
        );
    }

    @Transactional
    public void deleteProject(String projectId) {
        Project project = projectRepository.findById(projectId)
                .orElseThrow(() -> new IllegalArgumentException("삭제할 프로젝트를 찾을 수 없습니다."));

        Path projectDir = Paths
                .get(System.getProperty("user.dir"), "data")
                .resolve(project.getProj_mem())
                .resolve(project.getProj_code())
                .toAbsolutePath()
                .normalize();

        roomRepository.deleteByRoomProj(projectId);
        projectRepository.delete(project);
        projectRepository.flush();

        deleteDirectory(projectDir);
    }

    private void deleteDirectory(Path targetDir) {
        Path dataRoot = Paths
                .get(System.getProperty("user.dir"), "data")
                .toAbsolutePath()
                .normalize();

        Path normalizedTargetDir = targetDir.toAbsolutePath().normalize();

        if (!normalizedTargetDir.startsWith(dataRoot)) {
            throw new IllegalArgumentException("삭제할 수 없는 경로입니다.");
        }

        if (!Files.exists(normalizedTargetDir)) {
            log.info("삭제할 프로젝트 폴더가 없습니다. path={}", normalizedTargetDir);
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
