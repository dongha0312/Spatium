package com.pknu.spatium_backend.service;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockMultipartFile;

import com.pknu.spatium_backend.exception.ApiException;

class FileValidationServiceTest {

    private final FileValidationService validation = new FileValidationService();

    @Test
    void acceptsGlbVersionTwoWithMatchingDeclaredLength() {
        MockMultipartFile file = new MockMultipartFile(
                "file",
                "chair.glb",
                "model/gltf-binary",
                glbHeader(12));

        assertDoesNotThrow(() -> validation.validateGlb(file));
    }

    @Test
    void rejectsGlbWithForgedDeclaredLength() {
        MockMultipartFile file = new MockMultipartFile(
                "file",
                "chair.glb",
                "model/gltf-binary",
                glbHeader(99));

        ApiException error = assertThrows(ApiException.class, () -> validation.validateGlb(file));
        assertEquals("INVALID_FILE_TYPE", error.getCode());
    }

    @Test
    void validatesJsonAndUsdzMagicBytes() {
        MockMultipartFile metadata = new MockMultipartFile(
                "metadata",
                "metadata.json",
                "application/json",
                "{\"objects\":[]}".getBytes());
        MockMultipartFile usdz = new MockMultipartFile(
                "file",
                "scene.usdz",
                "model/vnd.usdz+zip",
                new byte[] {'P', 'K', 3, 4, 0});

        assertDoesNotThrow(() -> validation.validateJson(metadata));
        assertDoesNotThrow(() -> validation.validateUsdz(usdz));
    }

    @Test
    void rejectsImageWhoseBytesDoNotMatchItsExtension() {
        MockMultipartFile image = new MockMultipartFile(
                "image",
                "photo.png",
                "image/png",
                "not-a-png".getBytes());

        ApiException error = assertThrows(ApiException.class, () -> validation.validateAiImage(image));
        assertEquals("INVALID_IMAGE_FILE", error.getCode());
    }

    private byte[] glbHeader(int declaredLength) {
        return ByteBuffer.allocate(12)
                .order(ByteOrder.LITTLE_ENDIAN)
                .put(new byte[] {'g', 'l', 'T', 'F'})
                .putInt(2)
                .putInt(declaredLength)
                .array();
    }
}
