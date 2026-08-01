package com.example.doenggameflux.component;

public class AiCapacityExceededException extends RuntimeException {

    public AiCapacityExceededException() {
        super("AI outbound concurrency capacity is full");
    }
}
