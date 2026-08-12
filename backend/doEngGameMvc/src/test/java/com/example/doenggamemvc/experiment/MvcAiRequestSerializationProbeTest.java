package com.example.doenggamemvc.experiment;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.web.client.RestTemplate;

class MvcAiRequestSerializationProbeTest {

    @Test
    void serializeOnlyUsesTheRestTemplateJsonConverterAndExpectedFields() {
        MvcAiRequestSerializationProbe probe =
                new MvcAiRequestSerializationProbe(new RestTemplate());

        Map<String, Object> result = probe.serialize("aGVsbG8=", "happy");
        Map<?, ?> serialization = (Map<?, ?>) result.get("serialization");

        assertEquals(true, result.get("result"));
        assertTrue((Integer) serialization.get("serializedBytes") > 0);
        assertEquals("application/json", serialization.get("contentType"));
        assertTrue(((String) serialization.get("sha256")).matches("[0-9a-f]{64}"));
    }
}
