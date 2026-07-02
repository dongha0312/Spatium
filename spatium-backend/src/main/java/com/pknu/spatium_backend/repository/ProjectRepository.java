package com.pknu.spatium_backend.repository;

import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import com.pknu.spatium_backend.model.Project;

@Repository
public interface ProjectRepository extends JpaRepository<Project, String>{

    @Query("SELECT p FROM Project p WHERE p.proj_mem = :memID")
    List<Project> getProjectList(@Param("memID") String memID);

}
