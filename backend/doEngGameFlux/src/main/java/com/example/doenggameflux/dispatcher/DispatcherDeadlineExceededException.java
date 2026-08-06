package com.example.doenggameflux.dispatcher;

public final class DispatcherDeadlineExceededException extends RuntimeException {

    public DispatcherDeadlineExceededException(String dispatcher, String requestId, String phase) {
        super("dispatcher deadline exceeded: dispatcher=" + dispatcher
                + ", requestId=" + requestId
                + ", phase=" + phase);
    }
}
