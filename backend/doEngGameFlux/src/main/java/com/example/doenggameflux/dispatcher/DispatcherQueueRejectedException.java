package com.example.doenggameflux.dispatcher;

import reactor.core.publisher.Sinks;

public final class DispatcherQueueRejectedException extends RuntimeException {

    public DispatcherQueueRejectedException(
            String dispatcher,
            String requestId,
            Sinks.EmitResult emitResult) {
        super("dispatcher queue rejected: dispatcher=" + dispatcher
                + ", requestId=" + requestId
                + ", emitResult=" + emitResult);
    }
}
