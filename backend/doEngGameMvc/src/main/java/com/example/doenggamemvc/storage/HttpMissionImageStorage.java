package com.example.doenggamemvc.storage;

import com.example.doenggamemvc.config.ExternalServiceProperties;
import com.example.doenggamemvc.dto.StorageResponse;
import java.net.URI;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.util.UriComponentsBuilder;

@Component
public class HttpMissionImageStorage implements MissionImageStorage {

    private final RestTemplate restTemplate;
    private final String storageBaseUrl;

    public HttpMissionImageStorage(
            RestTemplate externalRestTemplate,
            ExternalServiceProperties properties) {
        this.restTemplate = externalRestTemplate;
        this.storageBaseUrl = properties.getStorageBaseUrl();
    }

    @Override
    public String upload(String objectKey, byte[] image) {
        URI uri = UriComponentsBuilder
                .fromHttpUrl(storageBaseUrl)
                .path("/storage/object")
                .queryParam("key", objectKey)
                .build()
                .encode()
                .toUri();

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.IMAGE_JPEG);
        ResponseEntity<StorageResponse> response = restTemplate.exchange(
                uri,
                HttpMethod.PUT,
                new HttpEntity<>(image, headers),
                StorageResponse.class);

        StorageResponse body = response.getBody();
        if (body == null || body.getKey() == null) {
            throw new IllegalStateException("Storage response key is empty");
        }
        return body.getKey();
    }
}
