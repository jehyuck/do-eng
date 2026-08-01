package com.example.doenggameflux.s3;

import com.example.doenggameflux.config.ExternalServiceProperties;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

@Component
@ConditionalOnProperty(
        name = "doeng.storage.mode",
        havingValue = "http",
        matchIfMissing = true)
public class HttpMissionImageStorage implements MissionImageStorage {

    private final WebClient webClient;

    public HttpMissionImageStorage(
            ExternalServiceProperties properties,
            @Qualifier("externalWebClientBuilder")
            WebClient.Builder externalWebClientBuilder) {
        this.webClient = externalWebClientBuilder.clone()
                .baseUrl(properties.getStorageBaseUrl())
                .build();
    }

    @Override
    public Mono<String> upload(String objectKey, byte[] image) {
        return webClient.put()
                .uri(uriBuilder -> uriBuilder
                        .path("/storage/object")
                        .queryParam("key", objectKey)
                        .build())
                .contentType(MediaType.IMAGE_JPEG)
                .bodyValue(image)
                .retrieve()
                .bodyToMono(StorageResponse.class)
                .map(StorageResponse::getKey);
    }

    public static class StorageResponse {

        private String key;

        public String getKey() {
            return key;
        }

        public void setKey(String key) {
            this.key = key;
        }
    }
}
