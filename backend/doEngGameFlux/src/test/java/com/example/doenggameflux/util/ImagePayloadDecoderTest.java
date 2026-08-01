package com.example.doenggameflux.util;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;

class ImagePayloadDecoderTest {

    @Test
    void decodesDataUrlAndRawBase64() {
        byte[] expected = "mission-image".getBytes(StandardCharsets.UTF_8);
        String base64 = "bWlzc2lvbi1pbWFnZQ==";

        assertArrayEquals(expected,
                ImagePayloadDecoder.decodeDataUrlOrBase64(
                        "data:image/jpeg;base64," + base64));
        assertArrayEquals(expected,
                ImagePayloadDecoder.decodeDataUrlOrBase64(base64));
    }

    @Test
    void rejectsMissingPayload() {
        assertThrows(IllegalArgumentException.class,
                () -> ImagePayloadDecoder.decodeDataUrlOrBase64(""));
    }
}
