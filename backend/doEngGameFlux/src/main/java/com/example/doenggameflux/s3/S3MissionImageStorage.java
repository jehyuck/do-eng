package com.example.doenggameflux.s3;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;
import software.amazon.awssdk.core.async.AsyncRequestBody;
import software.amazon.awssdk.services.s3.S3AsyncClient;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

@Component
@ConditionalOnProperty(name = "doeng.storage.mode", havingValue = "s3")
public class S3MissionImageStorage implements MissionImageStorage {

    private final S3AsyncClient s3AsyncClient;
    private final String bucket;

    public S3MissionImageStorage(
            S3AsyncClient s3AsyncClient,
            @Value("${cloud.aws.s3.bucket}") String bucket) {
        this.s3AsyncClient = s3AsyncClient;
        this.bucket = bucket;
    }

    @Override
    public Mono<String> upload(String objectKey, byte[] image) {
        PutObjectRequest request = PutObjectRequest.builder()
                .bucket(bucket)
                .key(objectKey)
                .contentType("image/jpeg")
                .contentLength((long) image.length)
                .build();

        return Mono.fromFuture(
                        s3AsyncClient.putObject(request, AsyncRequestBody.fromBytes(image)))
                .thenReturn(objectKey);
    }
}
