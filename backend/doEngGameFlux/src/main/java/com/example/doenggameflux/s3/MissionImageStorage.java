package com.example.doenggameflux.s3;

import reactor.core.publisher.Mono;

public interface MissionImageStorage {

    Mono<String> upload(String objectKey, byte[] image);
}
