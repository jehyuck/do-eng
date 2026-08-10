package com.example.doenggamemvc.util;

import java.util.Base64;

public final class ImagePayloadDecoder {

    private ImagePayloadDecoder() {
    }

    public static byte[] decodeDataUrlOrBase64(String image) {
        if (image == null || image.isBlank()) {
            throw new IllegalArgumentException("Image payload is required");
        }
        int separatorIndex = image.indexOf(',');
        String encoded = separatorIndex >= 0
                ? image.substring(separatorIndex + 1)
                : image;
        return Base64.getDecoder().decode(encoded);
    }
}
