package com.pknu.spatium_backend.service;

import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Locale;
import java.util.Set;

import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;

import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.pknu.spatium_backend.exception.ApiException;

@Service
public class FileValidationService {

    private static final long AI_IMAGE_MAX_BYTES = 10L * 1024L * 1024L;
    private static final long JSON_MAX_BYTES = 10L * 1024L * 1024L;
    private static final long MODEL_MAX_BYTES = 100L * 1024L * 1024L;
    private static final long IMAGE_MAX_PIXELS = 40_000_000L;

    private static final Set<String> IMAGE_MIME_TYPES = Set.of(
            "image/png", "image/jpeg", "image/jpg", "image/webp", "application/octet-stream");
    private static final Set<String> GLB_MIME_TYPES = Set.of(
            "model/gltf-binary", "model/gltf+binary", "application/octet-stream");
    private static final Set<String> USDZ_MIME_TYPES = Set.of(
            "model/vnd.usdz+zip", "model/usd", "application/zip", "application/octet-stream");
    private static final Set<String> JSON_MIME_TYPES = Set.of(
            "application/json", "text/json", "application/octet-stream");

    private final ObjectMapper objectMapper = new ObjectMapper();

    public void validateAiImage(MultipartFile file) {
        requirePresentAndWithinSize(file, AI_IMAGE_MAX_BYTES, "INVALID_IMAGE_FILE", "이미지 파일이 올바르지 않습니다.");
        requireExtension(file, Set.of("png", "jpg", "jpeg", "webp"), "이미지는 PNG, JPEG, WebP 형식만 가능합니다.");
        requireMime(file, IMAGE_MIME_TYPES, "이미지 MIME 형식이 올바르지 않습니다.");

        byte[] header = readHeader(file, 12, "이미지 파일을 읽을 수 없습니다.");
        boolean png = header.length >= 8
                && (header[0] & 0xff) == 0x89 && header[1] == 'P' && header[2] == 'N' && header[3] == 'G'
                && header[4] == 0x0d && header[5] == 0x0a && header[6] == 0x1a && header[7] == 0x0a;
        boolean jpeg = header.length >= 3
                && (header[0] & 0xff) == 0xff && (header[1] & 0xff) == 0xd8 && (header[2] & 0xff) == 0xff;
        boolean webp = header.length >= 12
                && header[0] == 'R' && header[1] == 'I' && header[2] == 'F' && header[3] == 'F'
                && header[8] == 'W' && header[9] == 'E' && header[10] == 'B' && header[11] == 'P';
        if (!png && !jpeg && !webp) {
            throw new ApiException(400, "INVALID_IMAGE_FILE", "실제 이미지 형식이 PNG, JPEG 또는 WebP가 아닙니다.");
        }
        if (png || jpeg) {
            validateRasterDimensions(file);
        }
    }

    public void validateGlb(MultipartFile file) {
        requirePresentAndWithinSize(file, MODEL_MAX_BYTES, "INVALID_FILE", "GLB 파일이 올바르지 않습니다.");
        requireExtension(file, Set.of("glb"), "가구 모델은 .glb 파일이어야 합니다.");
        requireMime(file, GLB_MIME_TYPES, "GLB MIME 형식이 올바르지 않습니다.");

        byte[] header = readHeader(file, 12, "GLB 파일을 읽을 수 없습니다.");
        if (header.length != 12
                || header[0] != 'g' || header[1] != 'l' || header[2] != 'T' || header[3] != 'F') {
            throw new ApiException(400, "INVALID_FILE_TYPE", "올바른 GLB 2.0 파일이 아닙니다.");
        }

        ByteBuffer buffer = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN);
        long version = Integer.toUnsignedLong(buffer.getInt(4));
        long declaredLength = Integer.toUnsignedLong(buffer.getInt(8));
        if (version != 2L || declaredLength != file.getSize()) {
            throw new ApiException(400, "INVALID_FILE_TYPE", "올바른 GLB 2.0 파일이 아닙니다.");
        }
    }

    public void validateUsdz(MultipartFile file) {
        requirePresentAndWithinSize(file, MODEL_MAX_BYTES, "INVALID_FILE", "USDZ 파일이 올바르지 않습니다.");
        requireExtension(file, Set.of("usdz"), "3D 모델은 .usdz 파일이어야 합니다.");
        requireMime(file, USDZ_MIME_TYPES, "USDZ MIME 형식이 올바르지 않습니다.");

        byte[] header = readHeader(file, 4, "USDZ 파일을 읽을 수 없습니다.");
        if (header.length != 4 || header[0] != 'P' || header[1] != 'K' || header[2] != 3 || header[3] != 4) {
            throw new ApiException(400, "INVALID_FILE_TYPE", "올바른 USDZ 파일이 아닙니다.");
        }
    }

    public void validateJson(MultipartFile file) {
        requirePresentAndWithinSize(file, JSON_MAX_BYTES, "INVALID_FILE", "metadata 파일이 올바르지 않습니다.");
        requireExtension(file, Set.of("json"), "metadata는 .json 파일이어야 합니다.");
        requireMime(file, JSON_MIME_TYPES, "metadata MIME 형식이 올바르지 않습니다.");

        try (InputStream input = file.getInputStream()) {
            JsonNode root = objectMapper.readTree(input);
            if (root == null) {
                throw new ApiException(400, "INVALID_FILE_TYPE", "metadata JSON 형식이 올바르지 않습니다.");
            }
        } catch (ApiException e) {
            throw e;
        } catch (IOException e) {
            throw new ApiException(400, "INVALID_FILE_TYPE", "metadata JSON 형식이 올바르지 않습니다.");
        }
    }

    private void requirePresentAndWithinSize(
            MultipartFile file,
            long maxBytes,
            String code,
            String message) {
        if (file == null || file.isEmpty() || file.getSize() <= 0 || file.getSize() > maxBytes) {
            throw new ApiException(400, code, message);
        }
    }

    private void requireExtension(MultipartFile file, Set<String> extensions, String message) {
        String name = file.getOriginalFilename();
        if (name == null || name.isBlank()) {
            return;
        }
        int separator = name.lastIndexOf('.');
        String extension = separator >= 0 ? name.substring(separator + 1).toLowerCase(Locale.ROOT) : "";
        if (!extensions.contains(extension)) {
            throw new ApiException(400, "INVALID_FILE_TYPE", message);
        }
    }

    private void requireMime(MultipartFile file, Set<String> allowed, String message) {
        String contentType = file.getContentType();
        if (contentType == null || contentType.isBlank()) {
            return;
        }
        String normalized = contentType.split(";", 2)[0].trim().toLowerCase(Locale.ROOT);
        if (!allowed.contains(normalized)) {
            throw new ApiException(400, "INVALID_FILE_TYPE", message);
        }
    }

    private byte[] readHeader(MultipartFile file, int length, String message) {
        try (InputStream input = file.getInputStream()) {
            return input.readNBytes(length);
        } catch (IOException e) {
            throw new ApiException(400, "INVALID_FILE", message);
        }
    }

    private void validateRasterDimensions(MultipartFile file) {
        try (InputStream input = file.getInputStream();
                ImageInputStream imageInput = ImageIO.createImageInputStream(input)) {
            if (imageInput == null) {
                throw new ApiException(400, "INVALID_IMAGE_FILE", "이미지 파일을 해석할 수 없습니다.");
            }
            var readers = ImageIO.getImageReaders(imageInput);
            if (!readers.hasNext()) {
                throw new ApiException(400, "INVALID_IMAGE_FILE", "이미지 파일을 해석할 수 없습니다.");
            }

            ImageReader reader = readers.next();
            try {
                reader.setInput(imageInput, true, true);
                int width = reader.getWidth(0);
                int height = reader.getHeight(0);
                long pixels = (long) width * height;
                if (width <= 0 || height <= 0 || pixels > IMAGE_MAX_PIXELS) {
                    throw new ApiException(400, "INVALID_IMAGE_FILE", "이미지 해상도가 올바르지 않습니다.");
                }
            } finally {
                reader.dispose();
            }
        } catch (ApiException e) {
            throw e;
        } catch (IOException | RuntimeException e) {
            throw new ApiException(400, "INVALID_IMAGE_FILE", "이미지 파일을 해석할 수 없습니다.");
        }
    }
}
