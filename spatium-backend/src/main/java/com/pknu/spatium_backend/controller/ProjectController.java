package com.pknu.spatium_backend.controller;

import org.springframework.web.bind.annotation.RestController;

import com.pknu.spatium_backend.service.ProjectService;

import lombok.RequiredArgsConstructor;

@RestController
@RequiredArgsConstructor
public class ProjectController {

    private final ProjectService projectService;

}
