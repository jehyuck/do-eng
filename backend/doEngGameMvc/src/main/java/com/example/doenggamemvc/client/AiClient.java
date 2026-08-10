package com.example.doenggamemvc.client;

import com.example.doenggamemvc.config.ExternalServiceProperties;
import com.example.doenggamemvc.dto.AiDecisionResult;
import java.util.HashMap;
import java.util.Map;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

@Component
public class AiClient {

    private final RestTemplate restTemplate;
    private final String faceUrl;

    public AiClient(
            RestTemplate externalRestTemplate,
            ExternalServiceProperties properties) {
        this.restTemplate = externalRestTemplate;
        this.faceUrl = properties.getAiBaseUrl() + "/face";
    }

    public AiDecisionResult decide(String image, String answer) {
        Map<String, String> requestBody = new HashMap<>();
        requestBody.put("answer", answer);
        requestBody.put("image", image);

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.setAccept(java.util.Collections.singletonList(
                MediaType.APPLICATION_JSON));

        AiDecisionResult response = restTemplate.postForObject(
                faceUrl,
                new HttpEntity<>(requestBody, headers),
                AiDecisionResult.class);
        if (response == null) {
            throw new IllegalStateException("AI response body is empty");
        }
        return response;
    }
}
