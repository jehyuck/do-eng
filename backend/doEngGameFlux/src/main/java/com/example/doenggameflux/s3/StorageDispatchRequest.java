package com.example.doenggameflux.s3;

import java.util.Objects;

public final class StorageDispatchRequest {

    private final String objectKey;
    private final byte[] image;

    public StorageDispatchRequest(String objectKey, byte[] image) {
        this.objectKey = Objects.requireNonNull(objectKey, "objectKey");
        this.image = Objects.requireNonNull(image, "image");
    }

    public String getObjectKey() {
        return objectKey;
    }

    public byte[] getImage() {
        return image;
    }
}
