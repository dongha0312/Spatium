package com.pknu.spatium_backend.storage;

import java.io.IOException;
import java.io.InputStream;

import org.springframework.core.io.Resource;

/**
 * Object-key based file storage boundary. Callers store portable keys rather
 * than host-specific absolute paths so another storage implementation can be
 * introduced without changing the domain services.
 */
public interface FileStorage {

    void store(String objectKey, InputStream inputStream) throws IOException;

    Resource load(String objectKey) throws IOException;

    boolean exists(String objectKey);

    void delete(String objectKey) throws IOException;
}
