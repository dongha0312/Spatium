package com.pknu.spatium_backend.storage;

import java.io.IOException;
import java.util.Collection;
import java.util.List;

import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@Component
@RequiredArgsConstructor
@Slf4j
public class FileStorageCleanup {

    private final FileStorage fileStorage;

    public void deleteAfterCommit(Collection<String> objectKeys) {
        List<String> keys = normalizedKeys(objectKeys);
        if (keys.isEmpty()) {
            return;
        }

        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    deleteNow(keys);
                }
            });
        } else {
            deleteNow(keys);
        }
    }

    public void deleteOnRollback(Collection<String> objectKeys) {
        List<String> keys = normalizedKeys(objectKeys);
        if (keys.isEmpty() || !TransactionSynchronizationManager.isSynchronizationActive()) {
            return;
        }

        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCompletion(int status) {
                if (status != TransactionSynchronization.STATUS_COMMITTED) {
                    deleteNow(keys);
                }
            }
        });
    }

    public void deleteNow(Collection<String> objectKeys) {
        for (String objectKey : normalizedKeys(objectKeys)) {
            try {
                fileStorage.delete(objectKey);
            } catch (IOException | RuntimeException e) {
                log.warn("Stored object cleanup failed. key={}", objectKey, e);
            }
        }
    }

    private List<String> normalizedKeys(Collection<String> objectKeys) {
        if (objectKeys == null) {
            return List.of();
        }
        return objectKeys.stream()
                .filter(key -> key != null && !key.isBlank())
                .distinct()
                .toList();
    }
}
