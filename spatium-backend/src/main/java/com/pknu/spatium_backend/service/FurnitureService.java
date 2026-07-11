package com.pknu.spatium_backend.service;

import org.springframework.stereotype.Service;

import com.pknu.spatium_backend.repository.FurnitureRepository;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@Service
@Slf4j
@RequiredArgsConstructor
public class FurnitureService {

    private final FurnitureRepository furnitureRepository;

}
