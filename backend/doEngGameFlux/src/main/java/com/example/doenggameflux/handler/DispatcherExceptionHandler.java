package com.example.doenggameflux.handler;

import com.example.doenggameflux.dispatcher.DispatcherDeadlineExceededException;
import com.example.doenggameflux.dispatcher.DispatcherQueueRejectedException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class DispatcherExceptionHandler {

    @ExceptionHandler(DispatcherQueueRejectedException.class)
    public ResponseEntity<String> handleQueueRejected(
            DispatcherQueueRejectedException exception) {
        return ResponseEntity
                .status(HttpStatus.SERVICE_UNAVAILABLE)
                .body(exception.getMessage());
    }

    @ExceptionHandler(DispatcherDeadlineExceededException.class)
    public ResponseEntity<String> handleDeadlineExceeded(
            DispatcherDeadlineExceededException exception) {
        return ResponseEntity
                .status(HttpStatus.GATEWAY_TIMEOUT)
                .body(exception.getMessage());
    }
}
