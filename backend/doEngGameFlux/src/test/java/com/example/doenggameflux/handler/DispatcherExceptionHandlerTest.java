package com.example.doenggameflux.handler;

import static org.junit.jupiter.api.Assertions.assertEquals;

import com.example.doenggameflux.dispatcher.DispatcherDeadlineExceededException;
import com.example.doenggameflux.dispatcher.DispatcherQueueRejectedException;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import reactor.core.publisher.Sinks;

class DispatcherExceptionHandlerTest {

    private final DispatcherExceptionHandler handler = new DispatcherExceptionHandler();

    @Test
    void queueRejectedMapsToServiceUnavailable() {
        ResponseEntity<String> response = handler.handleQueueRejected(
                new DispatcherQueueRejectedException(
                        "token",
                        "request-1",
                        Sinks.EmitResult.FAIL_OVERFLOW));

        assertEquals(HttpStatus.SERVICE_UNAVAILABLE, response.getStatusCode());
    }

    @Test
    void deadlineExceededMapsToGatewayTimeout() {
        ResponseEntity<String> response = handler.handleDeadlineExceeded(
                new DispatcherDeadlineExceededException(
                        "ai",
                        "request-1",
                        "DURING_EXECUTION"));

        assertEquals(HttpStatus.GATEWAY_TIMEOUT, response.getStatusCode());
    }
}
