package com.example.doenggameflux.s3;

import com.example.doenggameflux.dispatcher.AbstractSinkDispatcher;
import com.example.doenggameflux.dispatcher.DispatcherSpec;
import com.example.doenggameflux.dispatcher.MissionExecutionContext;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

@Component
public final class StorageDispatcher extends AbstractSinkDispatcher<StorageDispatchRequest, String> {

    private final MissionImageStorage missionImageStorage;

    public StorageDispatcher(
            MissionImageStorage missionImageStorage,
            @Value("${doeng.dispatcher.storage.concurrency:100}") int concurrency,
            @Value("${doeng.dispatcher.storage.queue-capacity:2000}") int queueCapacity) {
        super(new DispatcherSpec("storage", concurrency, queueCapacity));
        this.missionImageStorage = missionImageStorage;
    }

    @Override
    protected Mono<String> invoke(
            MissionExecutionContext context,
            StorageDispatchRequest input) {
        return missionImageStorage.upload(input.getObjectKey(), input.getImage());
    }
}
