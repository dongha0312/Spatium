package com.pknu.spatium_backend.service;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.OptionalLong;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import com.pknu.spatium_backend.exception.ApiException;

import lombok.Getter;
import lombok.extern.slf4j.Slf4j;

@Service
@Slf4j
public class AiGatewayService {

    public static final String INTERNAL_API_KEY_HEADER = "X-Internal-Api-Key";
    public static final String AI_METADATA_HEADER = "X-Spatium-AI-Metadata";

    private static final int MAX_ERROR_BODY_BYTES = 64 * 1024;

    private final HttpClient httpClient;
    private final URI baseUri;
    private final String internalApiKey;
    private final Duration requestTimeout;

    public AiGatewayService(
            @Value("${spatium.ai.base-url:http://127.0.0.1:8000}") String baseUrl,
            @Value("${spatium.ai.internal-api-key:}") String internalApiKey,
            @Value("${spatium.ai.request-timeout:PT15M}") Duration requestTimeout) {
        String normalizedBaseUrl = baseUrl.endsWith("/") ? baseUrl : baseUrl + "/";
        this.baseUri = URI.create(normalizedBaseUrl);
        if (!"http".equalsIgnoreCase(baseUri.getScheme()) && !"https".equalsIgnoreCase(baseUri.getScheme())) {
            throw new IllegalArgumentException("spatium.ai.base-url must use http or https");
        }
        this.internalApiKey = internalApiKey == null ? "" : internalApiKey.trim();
        this.requestTimeout = requestTimeout;
        this.httpClient = HttpClient.newBuilder()
                // Uvicorn serves HTTP/1.1. Java 17 otherwise attempts an h2c
                // upgrade, which can corrupt a streamed multipart exchange.
                .version(HttpClient.Version.HTTP_1_1)
                .connectTimeout(Duration.ofSeconds(10))
                .followRedirects(HttpClient.Redirect.NEVER)
                .build();
    }

    public AiBinaryResponse removeBackground(MultipartFile image, Map<String, String> parameters) {
        return postMultipart("v1/remove-background", image, parameters, List.of("image/png"), "background-removed.png");
    }

    public AiBinaryResponse imageTo3d(MultipartFile image, Map<String, String> parameters) {
        return postMultipart(
                "v1/image-to-3d",
                image,
                parameters,
                List.of("model/gltf-binary", "application/octet-stream"),
                "generated-model.glb");
    }

    private AiBinaryResponse postMultipart(
            String relativePath,
            MultipartFile image,
            Map<String, String> parameters,
            List<String> allowedResponseTypes,
            String downloadName) {
        if (internalApiKey.isBlank()) {
            throw new ApiException(503, "AI_NOT_CONFIGURED", "AI 내부 인증 키가 설정되지 않았습니다.");
        }

        String boundary = "spatium-" + UUID.randomUUID().toString().replace("-", "");
        HttpRequest.BodyPublisher body = multipartBody(boundary, image, parameters);
        HttpRequest request = HttpRequest.newBuilder(baseUri.resolve(relativePath))
                .timeout(requestTimeout)
                .header("Accept", String.join(", ", allowedResponseTypes))
                .header("Content-Type", "multipart/form-data; boundary=" + boundary)
                .header(INTERNAL_API_KEY_HEADER, internalApiKey)
                .POST(body)
                .build();

        try {
            HttpResponse<InputStream> response = httpClient.send(request, HttpResponse.BodyHandlers.ofInputStream());
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                handleUpstreamError(response);
            }

            String contentType = response.headers().firstValue("Content-Type")
                    .map(value -> value.split(";", 2)[0].trim().toLowerCase())
                    .orElse("application/octet-stream");
            if (!allowedResponseTypes.contains(contentType)) {
                response.body().close();
                throw new ApiException(502, "AI_INVALID_RESPONSE", "AI 서버가 올바르지 않은 파일 형식을 반환했습니다.");
            }

            String metadata = response.headers().firstValue(AI_METADATA_HEADER).orElse("");
            if (metadata.length() > 8192) {
                response.body().close();
                throw new ApiException(502, "AI_INVALID_RESPONSE", "AI 서버의 metadata 응답이 너무 큽니다.");
            }

            return new AiBinaryResponse(
                    response.body(),
                    contentType,
                    response.headers().firstValueAsLong("Content-Length"),
                    metadata,
                    downloadName);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new ApiException(503, "AI_REQUEST_INTERRUPTED", "AI 요청이 중단되었습니다.");
        } catch (IOException | UncheckedIOException e) {
            log.warn("AI upstream request failed. path={}", relativePath, e);
            throw new ApiException(502, "AI_SERVER_UNAVAILABLE", "AI 서버에 연결할 수 없습니다.");
        }
    }

    private HttpRequest.BodyPublisher multipartBody(
            String boundary,
            MultipartFile image,
            Map<String, String> parameters) {
        List<HttpRequest.BodyPublisher> publishers = new ArrayList<>();
        parameters.forEach((name, value) -> {
            if (value != null) {
                publishers.add(HttpRequest.BodyPublishers.ofByteArray((
                        "--" + boundary + "\r\n"
                                + "Content-Disposition: form-data; name=\"" + name + "\"\r\n\r\n"
                                + value + "\r\n").getBytes(StandardCharsets.UTF_8)));
            }
        });

        String originalName = image.getOriginalFilename();
        String safeName = originalName == null || originalName.isBlank() ? "image.png" : originalName;
        safeName = safeName.replaceAll("[\\r\\n\\\"]", "_");
        String contentType = image.getContentType() == null || image.getContentType().isBlank()
                ? "application/octet-stream"
                : image.getContentType();

        publishers.add(HttpRequest.BodyPublishers.ofByteArray((
                "--" + boundary + "\r\n"
                        + "Content-Disposition: form-data; name=\"image\"; filename=\"" + safeName + "\"\r\n"
                        + "Content-Type: " + contentType + "\r\n\r\n")
                .getBytes(StandardCharsets.UTF_8)));
        publishers.add(HttpRequest.BodyPublishers.ofInputStream(() -> {
            try {
                return image.getInputStream();
            } catch (IOException e) {
                throw new UncheckedIOException(e);
            }
        }));
        publishers.add(HttpRequest.BodyPublishers.ofByteArray(
                ("\r\n--" + boundary + "--\r\n").getBytes(StandardCharsets.UTF_8)));

        return HttpRequest.BodyPublishers.concat(publishers.toArray(HttpRequest.BodyPublisher[]::new));
    }

    private void handleUpstreamError(HttpResponse<InputStream> response) throws IOException {
        try (InputStream body = response.body()) {
            String errorBody = new String(body.readNBytes(MAX_ERROR_BODY_BYTES), StandardCharsets.UTF_8);
            log.warn("AI upstream error. status={}, body={}", response.statusCode(), errorBody);
        }

        int status = response.statusCode();
        if (status == 400 || status == 422) {
            throw new ApiException(400, "AI_INVALID_REQUEST", "AI 요청 값이 올바르지 않습니다.");
        }
        if (status == 413) {
            throw new ApiException(400, "AI_IMAGE_TOO_LARGE", "AI 이미지 파일이 너무 큽니다.");
        }
        throw new ApiException(502, "AI_UPSTREAM_ERROR", "AI 서버가 요청을 처리하지 못했습니다.");
    }

    @Getter
    public static final class AiBinaryResponse implements AutoCloseable {
        private final InputStream body;
        private final String contentType;
        private final OptionalLong contentLength;
        private final String metadata;
        private final String downloadName;

        public AiBinaryResponse(
                InputStream body,
                String contentType,
                OptionalLong contentLength,
                String metadata,
                String downloadName) {
            this.body = body;
            this.contentType = contentType;
            this.contentLength = contentLength;
            this.metadata = metadata;
            this.downloadName = downloadName;
        }

        @Override
        public void close() throws IOException {
            body.close();
        }
    }
}
