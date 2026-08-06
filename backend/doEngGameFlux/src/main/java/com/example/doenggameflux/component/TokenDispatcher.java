package com.example.doenggameflux.component;

import com.example.doenggameflux.dispatcher.AbstractSinkDispatcher;
import com.example.doenggameflux.dispatcher.DispatcherSpec;
import com.example.doenggameflux.dispatcher.MissionExecutionContext;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

@Component
public final class TokenDispatcher extends AbstractSinkDispatcher<String, Long> {

    private final TokenComponent tokenComponent;

    public TokenDispatcher(
            TokenComponent tokenComponent,
            @Value("${doeng.dispatcher.token.concurrency:100}") int concurrency,
            @Value("${doeng.dispatcher.token.queue-capacity:2000}") int queueCapacity) {
        super(new DispatcherSpec("token", concurrency, queueCapacity));
        this.tokenComponent = tokenComponent;
    }

    @Override
    protected Mono<Long> invoke(MissionExecutionContext context, String authorization) {
        return tokenComponent.jwtConfirm(authorization);
    }
}
