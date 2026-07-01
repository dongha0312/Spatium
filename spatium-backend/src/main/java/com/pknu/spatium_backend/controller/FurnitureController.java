package com.pknu.spatium_backend.controller;
import org.springframework.web.bind.annotation.RestController;
import com.pknu.spatium_backend.service.FurnitureService;

import lombok.RequiredArgsConstructor;

@RestController
@RequiredArgsConstructor
public class FurnitureController {

    private final FurnitureService furnitureService;

}
