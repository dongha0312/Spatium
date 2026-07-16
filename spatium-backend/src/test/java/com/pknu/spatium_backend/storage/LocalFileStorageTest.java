package com.pknu.spatium_backend.storage;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.ByteArrayInputStream;
import java.nio.file.Files;
import java.nio.file.Path;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class LocalFileStorageTest {

    @TempDir
    Path temporaryDirectory;

    @Test
    void storesLoadsAndDeletesByPortableObjectKey() throws Exception {
        LocalFileStorage storage = new LocalFileStorage(temporaryDirectory.toString());
        String key = "rooms/member-1/project-1/room-1/metadata.json";
        byte[] content = "{\"version\":1}".getBytes();

        storage.store(key, new ByteArrayInputStream(content));

        assertTrue(storage.exists(key));
        assertArrayEquals(content, storage.load(key).getInputStream().readAllBytes());

        storage.delete(key);

        assertFalse(storage.exists(key));
        assertFalse(Files.exists(temporaryDirectory.resolve("rooms")));
    }

    @Test
    void rejectsTraversalAndPlatformSpecificPaths() {
        LocalFileStorage storage = new LocalFileStorage(temporaryDirectory.toString());

        assertThrows(
                IllegalArgumentException.class,
                () -> storage.store("../outside.glb", new ByteArrayInputStream(new byte[] {1})));
        assertThrows(
                IllegalArgumentException.class,
                () -> storage.store("rooms\\member\\scene.usdz", new ByteArrayInputStream(new byte[] {1})));
        assertThrows(IllegalArgumentException.class, () -> storage.exists("/absolute/path.glb"));
    }
}
