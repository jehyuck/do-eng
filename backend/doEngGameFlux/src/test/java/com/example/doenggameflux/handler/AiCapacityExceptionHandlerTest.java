package com.example.doenggameflux.handler;

import static org.junit.jupiter.api.Assertions.assertEquals;

import com.example.doenggameflux.component.AiCapacityExceededException;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;

class AiCapacityExceptionHandlerTest {

    @Test
    void mapsAdmissionToExplicit503AndRetryAfter() {
        AiCapacityExceptionHandler handler = new AiCapacityExceptionHandler();
        var response = handler.handle(new AiCapacityExceededException());
        assertEquals(HttpStatus.SERVICE_UNAVAILABLE, response.getStatusCode());
        assertEquals("1", response.getHeaders().getFirst(HttpHeaders.RETRY_AFTER));
        assertEquals("AI_CAPACITY_EXCEEDED", response.getBody().get("error"));
    }
}
