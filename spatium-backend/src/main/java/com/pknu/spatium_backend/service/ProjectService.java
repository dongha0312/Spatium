package com.pknu.spatium_backend.service;

import java.util.List;
import java.util.UUID;

import org.springframework.stereotype.Service;

import com.pknu.spatium_backend.dto.ProjectDTO.ResponseProjectCreateDTO;
import com.pknu.spatium_backend.dto.ProjectDTO.ResponseProjectListDTO;
import com.pknu.spatium_backend.model.Project;
import com.pknu.spatium_backend.repository.ProjectRepository;

import jakarta.transaction.Transactional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@Service
@Slf4j
@RequiredArgsConstructor
public class ProjectService {
    
    private final ProjectRepository projectRepository;

    public List<ResponseProjectListDTO> getProjectList(String memID){
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
            .proj_code(UUID.randomUUID().toString().substring(0,30))
            .proj_mem(projectMem)
            .proj_name(projectName)
            .build();

        Project savedProject = projectRepository.save(project);

        return new ResponseProjectCreateDTO(
            savedProject.getProj_code(),
            savedProject.getProj_name()
        );
    }

}
