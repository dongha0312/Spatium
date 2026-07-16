package com.pknu.spatium_backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockMultipartFile;

import com.pknu.spatium_backend.service.AiGatewayService.AiBinaryResponse;
import com.sun.net.httpserver.HttpServer;

class AiGatewayServiceTest {

    private HttpServer server;

    @AfterEach
    void stopServer() {
        if (server != null) {
            server.stop(0);
        }
    }

    @Test
    void forwardsInternalKeyAndMultipartThenStreamsBinaryResponse() throws Exception {
        AtomicReference<String> receivedKey = new AtomicReference<>();
        AtomicReference<String> upgradeHeader = new AtomicReference<>();
        AtomicReference<String> receivedBody = new AtomicReference<>();
        byte[] responseBytes = "png-result".getBytes(StandardCharsets.UTF_8);

        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/v1/remove-background", exchange -> {
            receivedKey.set(exchange.getRequestHeaders().getFirst(AiGatewayService.INTERNAL_API_KEY_HEADER));
            upgradeHeader.set(exchange.getRequestHeaders().getFirst("Upgrade"));
            receivedBody.set(new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.ISO_8859_1));
            exchange.getResponseHeaders().set("Content-Type", "image/png");
            exchange.getResponseHeaders().set(AiGatewayService.AI_METADATA_HEADER, "eyJ0ZXN0Ijp0cnVlfQ");
            exchange.sendResponseHeaders(200, responseBytes.length);
            exchange.getResponseBody().write(responseBytes);
            exchange.close();
        });
        server.start();

        AiGatewayService gateway = new AiGatewayService(
                "http://127.0.0.1:" + server.getAddress().getPort(),
                "internal-secret",
                Duration.ofSeconds(5));
        MockMultipartFile image = new MockMultipartFile(
                "image", "chair.png", "image/png", new byte[] {1, 2, 3});

        try (AiBinaryResponse response = gateway.removeBackground(
                image,
                Map.of("segmentation_provider", "yolo"))) {
            assertEquals("image/png", response.getContentType());
            assertEquals("eyJ0ZXN0Ijp0cnVlfQ", response.getMetadata());
            assertEquals("png-result", new String(response.getBody().readAllBytes(), StandardCharsets.UTF_8));
        }

        assertEquals("internal-secret", receivedKey.get());
        assertNull(upgradeHeader.get());
        assertTrue(receivedBody.get().contains("name=\"segmentation_provider\""));
        assertTrue(receivedBody.get().contains("yolo"));
        assertTrue(receivedBody.get().contains("filename=\"chair.png\""));
    }
}
