package com.example.doenggameflux.dispatcher;

import java.util.Objects;

public final class DispatcherSpec {

    private final String name;
    private final int concurrency;
    private final int queueCapacity;

    public DispatcherSpec(String name, int concurrency, int queueCapacity) {
        this.name = Objects.requireNonNull(name, "name");
        if (name.trim().isEmpty()) {
            throw new IllegalArgumentException("dispatcher name must not be blank");
        }
        if (concurrency <= 0) {
            throw new IllegalArgumentException("dispatcher concurrency must be positive");
        }
        if (queueCapacity < concurrency) {
            throw new IllegalArgumentException("queue capacity must be at least concurrency");
        }
        this.concurrency = concurrency;
        this.queueCapacity = queueCapacity;
    }

    public String getName() {
        return name;
    }

    public int getConcurrency() {
        return concurrency;
    }

    public int getQueueCapacity() {
        return queueCapacity;
    }
}
