package com.pknu.spatium_backend.repository.projection;

import java.time.LocalDateTime;

public interface ProjectSummaryProjection {

    String getProjectId();

    String getProjectName();

    Long getRoomCount();

    LocalDateTime getCreatedAt();

    LocalDateTime getLastActivity();
}
