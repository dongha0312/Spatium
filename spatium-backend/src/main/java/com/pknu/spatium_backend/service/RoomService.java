package com.pknu.spatium_backend.service;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.UUID;

import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@Service
@RequiredArgsConstructor
@Slf4j
public class RoomService {

    public void post3dData(
            String jsonDataFile,
            MultipartFile usdzDataFile
    ) throws IOException {

        if (jsonDataFile == null || jsonDataFile.isBlank()) {
            throw new IOException("metadata JSON 데이터가 비어 있습니다.");
        }

        if (usdzDataFile == null || usdzDataFile.isEmpty()) {
            throw new IOException("USDZ 파일이 비어 있습니다.");
        }

        Path uploadDir = Paths
                .get(System.getProperty("user.dir"), "uploads", "models")
                .toAbsolutePath()
                .normalize();

        Files.createDirectories(uploadDir);

        // 파일 명 앞에 UUID를 적어놓아서 중복 방지.
        String uploadId = UUID.randomUUID().toString();

        String jsonFileName = uploadId + "_metadata.json";

        String usdzOriginalName = usdzDataFile.getOriginalFilename();
        if (usdzOriginalName == null || usdzOriginalName.isBlank()) {
            usdzOriginalName = "room-scan.usdz";
        }

        String usdzFileName = uploadId + "_" + Path.of(usdzOriginalName)
                .getFileName()
                .toString();

        // 무슨 코드?
        Path jsonPath = uploadDir.resolve(jsonFileName).normalize();
        Path usdzPath = uploadDir.resolve(usdzFileName).normalize();

        log.info("업로드 폴더 = {}", uploadDir);
        log.info("JSON 저장 경로 = {}", jsonPath);
        log.info("USDZ 저장 경로 = {}", usdzPath);

        Files.writeString(
                jsonPath,
                jsonDataFile,
                StandardCharsets.UTF_8
        );

        Files.copy(
                usdzDataFile.getInputStream(),
                usdzPath,
                StandardCopyOption.REPLACE_EXISTING
        );
    }
}