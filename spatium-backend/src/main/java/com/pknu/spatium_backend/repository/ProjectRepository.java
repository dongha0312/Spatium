package com.pknu.spatium_backend.repository;

import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import com.pknu.spatium_backend.model.Project;
import com.pknu.spatium_backend.repository.projection.ProjectSummaryProjection;

@Repository
public interface ProjectRepository extends JpaRepository<Project, String>{

    @Query("SELECT p FROM Project p WHERE p.proj_mem = :memID")
    List<Project> getProjectList(@Param("memID") String memID);

    @Query("""
            SELECT
                p.proj_code AS projectId,
                p.proj_name AS projectName,
                COUNT(r.room_id) AS roomCount,
                p.proj_date AS createdAt,
                MAX(COALESCE(r.room_modified, r.room_created, p.proj_date)) AS lastActivity
            FROM Project p
            LEFT JOIN Room r ON r.room_proj = p.proj_code
            WHERE p.proj_mem = :memId
            GROUP BY p.proj_code, p.proj_name, p.proj_date
            ORDER BY MAX(COALESCE(r.room_modified, r.room_created, p.proj_date)) DESC
            """)
    List<ProjectSummaryProjection> findProjectSummaries(
            @Param("memId") String memId);
}
