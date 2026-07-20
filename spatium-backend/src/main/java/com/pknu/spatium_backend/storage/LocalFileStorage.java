package com.pknu.spatium_backend.storage;

import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.DirectoryNotEmptyException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.UUID;
import java.util.regex.Pattern;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Component;

import lombok.extern.slf4j.Slf4j;

@Component
@Slf4j
public class LocalFileStorage implements FileStorage {

    private static final Pattern SAFE_SEGMENT = Pattern.compile("[A-Za-z0-9._-]+");

    private final Path root;

    public LocalFileStorage(@Value("${spatium.storage.root:}") String configuredRoot) {
        Path workingDirectory = Path.of(System.getProperty("user.dir"))
                .toAbsolutePath()
                .normalize();
        Path backendDirectory = Files.isDirectory(workingDirectory.resolve("spatium-backend"))
                ? workingDirectory.resolve("spatium-backend")
                : workingDirectory;

        if (configuredRoot == null || configuredRoot.isBlank()) {
            this.root = backendDirectory.resolve("data").toAbsolutePath().normalize();
        } else {
            Path configured = Path.of(configuredRoot.trim());
            this.root = (configured.isAbsolute() ? configured : backendDirectory.resolve(configured))
                    .toAbsolutePath()
                    .normalize();
        }

        log.info("Local file storage root={}", this.root);
    }

    @Override
    public void store(String objectKey, InputStream inputStream) throws IOException {
        if (inputStream == null) {
            throw new IllegalArgumentException("inputStream is required");
        }

        Path target = resolve(objectKey);
        Files.createDirectories(target.getParent());
        Path temporary = target.resolveSibling(target.getFileName() + ".tmp-" + UUID.randomUUID());

        try (InputStream input = inputStream) {
            Files.copy(input, temporary, StandardCopyOption.REPLACE_EXISTING);
            try {
                Files.move(
                        temporary,
                        target,
                        StandardCopyOption.ATOMIC_MOVE,
                        StandardCopyOption.REPLACE_EXISTING);
            } catch (AtomicMoveNotSupportedException e) {
                Files.move(temporary, target, StandardCopyOption.REPLACE_EXISTING);
            }
        } finally {
            Files.deleteIfExists(temporary);
        }
    }

    @Override
    public Resource load(String objectKey) throws IOException {
        Path target = resolve(objectKey);
        if (!Files.isRegularFile(target)) {
            throw new FileNotFoundException("Stored object was not found: " + objectKey);
        }
        return new FileSystemResource(target);
    }

    @Override
    public boolean exists(String objectKey) {
        return Files.isRegularFile(resolve(objectKey));
    }

    @Override
    public void delete(String objectKey) throws IOException {
        Path target = resolve(objectKey);
        Files.deleteIfExists(target);
        removeEmptyParents(target.getParent());
    }

    private Path resolve(String objectKey) {
        if (objectKey == null || objectKey.isBlank()
                || objectKey.startsWith("/") || objectKey.startsWith("\\")
                || objectKey.contains("\\")) {
            throw new IllegalArgumentException("Invalid object key");
        }

        Path resolved = root;
        String[] segments = objectKey.split("/", -1);
        for (String segment : segments) {
            if (segment.isBlank() || ".".equals(segment) || "..".equals(segment)
                    || !SAFE_SEGMENT.matcher(segment).matches()) {
                throw new IllegalArgumentException("Invalid object key");
            }
            resolved = resolved.resolve(segment);
        }

        Path normalized = resolved.toAbsolutePath().normalize();
        if (!normalized.startsWith(root)) {
            throw new IllegalArgumentException("Invalid object key");
        }
        return normalized;
    }

    private void removeEmptyParents(Path directory) throws IOException {
        Path current = directory;
        while (current != null && !current.equals(root) && current.startsWith(root)) {
            try {
                Files.deleteIfExists(current);
            } catch (DirectoryNotEmptyException e) {
                return;
            }
            current = current.getParent();
        }
    }
}
