package com.example.doenggamemvc.experiment;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpOutputMessage;
import org.springframework.http.MediaType;
import org.springframework.http.converter.HttpMessageConverter;
import org.springframework.http.converter.json.MappingJackson2HttpMessageConverter;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

/** Experiment-only serialization boundary using the production RestTemplate converter. */
@Profile("experiment")
@Service
public class MvcAiRequestSerializationProbe {

    private final MappingJackson2HttpMessageConverter jacksonConverter;

    public MvcAiRequestSerializationProbe(RestTemplate externalRestTemplate) {
        this.jacksonConverter = findJacksonConverter(externalRestTemplate);
    }

    public Map<String, Object> serialize(String image, String answer) {
        Map<String, String> requestBody = new HashMap<>();
        requestBody.put("answer", answer);
        requestBody.put("image", image);

        ByteArrayHttpOutputMessage output = new ByteArrayHttpOutputMessage();
        try {
            jacksonConverter.write(requestBody, MediaType.APPLICATION_JSON, output);
        } catch (IOException exception) {
            throw new IllegalStateException("AI request serialization failed", exception);
        }

        byte[] serialized = output.bytes();
        Map<String, Object> serialization = new java.util.LinkedHashMap<>();
        serialization.put("result", serialized.length > 0);
        serialization.put("serializedBytes", serialized.length);
        serialization.put("contentType", output.getHeaders().getContentType() == null
                ? null
                : output.getHeaders().getContentType().toString());
        serialization.put("sha256", sha256(serialized));

        Map<String, Object> result = new java.util.LinkedHashMap<>();
        result.put("result", true);
        result.put("imageChars", image == null ? 0 : image.length());
        result.put("serialization", serialization);
        result.put("steps", new String[] {
            "JSON_DESERIALIZE", "AI_REQUEST_BUILD", "AI_JSON_SERIALIZE"
        });
        return result;
    }

    private static MappingJackson2HttpMessageConverter findJacksonConverter(
            RestTemplate externalRestTemplate) {
        List<HttpMessageConverter<?>> converters = externalRestTemplate.getMessageConverters();
        return converters.stream()
                .filter(MappingJackson2HttpMessageConverter.class::isInstance)
                .map(MappingJackson2HttpMessageConverter.class::cast)
                .findFirst()
                .orElseThrow(() -> new IllegalStateException(
                        "externalRestTemplate has no MappingJackson2HttpMessageConverter"));
    }

    private static String sha256(byte[] bytes) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(bytes);
            StringBuilder result = new StringBuilder(digest.length * 2);
            for (byte value : digest) {
                result.append(String.format("%02x", value));
            }
            return result.toString();
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }

    private static final class ByteArrayHttpOutputMessage implements HttpOutputMessage {
        private final HttpHeaders headers = new HttpHeaders();
        private final ByteArrayOutputStream body = new ByteArrayOutputStream();

        @Override
        public HttpHeaders getHeaders() {
            return headers;
        }

        @Override
        public OutputStream getBody() {
            return body;
        }

        private byte[] bytes() {
            return body.toByteArray();
        }
    }
}
