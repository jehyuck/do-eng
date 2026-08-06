package com.example.doenggameflux.dispatcher;

import reactor.core.publisher.Mono;

public interface SinkDispatcher<I, O> {

    Mono<O> dispatch(MissionExecutionContext context, I input);
}
