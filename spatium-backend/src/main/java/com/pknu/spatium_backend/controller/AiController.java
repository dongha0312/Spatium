package com.pknu.spatium_backend.controller;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;

import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

import com.pknu.spatium_backend.auth.AuthenticatedMemId;
import com.pknu.spatium_backend.auth.GpuAccessLimiter;
import com.pknu.spatium_backend.service.AiGatewayService;
import com.pknu.spatium_backend.service.AiGatewayService.AiBinaryResponse;
import com.pknu.spatium_backend.service.FileValidationService;

import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;

@RestController
@RequiredArgsConstructor
@RequestMapping("/api/ai")
public class AiController {

    private final AiGatewayService aiGatewayService;
    private final FileValidationService fileValidationService;
    private final GpuAccessLimiter gpuAccessLimiter;

    @PostMapping(path = "/remove-background", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<StreamingResponseBody> removeBackground(
            @AuthenticatedMemId String memId,
            HttpServletRequest request,
            @RequestPart("image") MultipartFile image,
            @RequestParam(name = "segmentation_provider", defaultValue = "yolo") String segmentationProvider,
            @RequestParam(name = "target_class", required = false) String targetClass,
            @RequestParam(name = "object_query", required = false) String objectQuery) {
        // 같은 IP의 GPU 작업 동시 실행 차단 (진행 중이면 429)
        String clientIp = request.getRemoteAddr();
        gpuAccessLimiter.acquire(clientIp);

        // 응답 스트리밍이 시작되면 해제 책임이 StreamingResponseBody로 넘어간다.
        //  - 그 전에 예외가 나면 여기서 해제해야 IP가 잠긴 채로 남지 않는다.
        boolean handedOff = false;
        try {
            fileValidationService.validateAiImage(image);

            Map<String, String> parameters = new LinkedHashMap<>();
            parameters.put("segmentation_provider", segmentationProvider);
            putIfText(parameters, "target_class", targetClass);
            putIfText(parameters, "object_query", objectQuery);

            ResponseEntity<StreamingResponseBody> response =
                    stream(aiGatewayService.removeBackground(image, parameters), clientIp);
            handedOff = true;
            return response;
        } finally {
            if (!handedOff) {
                gpuAccessLimiter.release(clientIp);
            }
        }
    }

    @PostMapping(path = "/image-to-3d", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<StreamingResponseBody> imageTo3d(
            @AuthenticatedMemId String memId,
            HttpServletRequest request,
            @RequestPart("image") MultipartFile image,
            @RequestParam(name = "foreground_ratio", required = false) Double foregroundRatio,
            @RequestParam(name = "mc_resolution", defaultValue = "256") int mcResolution,
            @RequestParam(name = "remove_background", defaultValue = "true") boolean removeBackground,
            @RequestParam(name = "background_removal", defaultValue = "yolo") String backgroundRemoval,
            @RequestParam(name = "segmentation_provider", required = false) String segmentationProvider,
            @RequestParam(name = "target_class", required = false) String targetClass,
            @RequestParam(name = "object_query", required = false) String objectQuery,
            @RequestParam(name = "provider", required = false) String provider,
            @RequestParam(name = "texture_resolution", defaultValue = "1024") int textureResolution,
            @RequestParam(name = "remesh", defaultValue = "none") String remesh) {
        // 같은 IP의 GPU 작업 동시 실행 차단 (진행 중이면 429)
        String clientIp = request.getRemoteAddr();
        gpuAccessLimiter.acquire(clientIp);

        boolean handedOff = false;
        try {
            fileValidationService.validateAiImage(image);

            Map<String, String> parameters = new LinkedHashMap<>();
            if (foregroundRatio != null) {
                parameters.put("foreground_ratio", foregroundRatio.toString());
            }
            parameters.put("mc_resolution", Integer.toString(mcResolution));
            parameters.put("remove_background", Boolean.toString(removeBackground));
            parameters.put("background_removal", backgroundRemoval);
            putIfText(parameters, "segmentation_provider", segmentationProvider);
            putIfText(parameters, "target_class", targetClass);
            putIfText(parameters, "object_query", objectQuery);
            putIfText(parameters, "provider", provider);
            parameters.put("texture_resolution", Integer.toString(textureResolution));
            parameters.put("remesh", remesh);

            ResponseEntity<StreamingResponseBody> response =
                    stream(aiGatewayService.imageTo3d(image, parameters), clientIp);
            handedOff = true;
            return response;
        } finally {
            if (!handedOff) {
                gpuAccessLimiter.release(clientIp);
            }
        }
    }

    private ResponseEntity<StreamingResponseBody> stream(AiBinaryResponse response, String clientIp) {
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.parseMediaType(response.getContentType()));
            headers.setContentDisposition(ContentDisposition.attachment()
                    .filename(response.getDownloadName(), StandardCharsets.UTF_8)
                    .build());
            if (!response.getMetadata().isBlank()) {
                headers.set(AiGatewayService.AI_METADATA_HEADER, response.getMetadata());
            }
            response.getContentLength().ifPresent(headers::setContentLength);

            StreamingResponseBody body = output -> {
                // 전송이 끝나야(또는 클라이언트 연결이 끊겨야) 작업이 완전히 종료된 것이므로
                // GPU 점유 해제는 여기서 한다. 컨트롤러 메서드 리턴 시점에 풀면 너무 이르다.
                try (response) {
                    response.getBody().transferTo(output);
                    output.flush();
                } finally {
                    gpuAccessLimiter.release(clientIp);
                }
            };
            return ResponseEntity.ok().headers(headers).body(body);
        } catch (RuntimeException e) {
            try {
                response.close();
            } catch (IOException ignored) {
                // The original response-building error is more useful to the caller.
            }
            // 여기서 던진 예외는 호출부(handedOff=false)의 finally가 받아 해제한다.
            throw e;
        }
    }

    private void putIfText(Map<String, String> parameters, String name, String value) {
        if (value != null && !value.isBlank()) {
            parameters.put(name, value.trim());
        }
    }
}
