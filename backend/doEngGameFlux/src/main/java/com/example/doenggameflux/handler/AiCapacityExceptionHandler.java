package com.example.doenggameflux.handler;

import com.example.doenggameflux.component.AiCapacityExceededException;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class AiCapacityExceptionHandler {

    @ExceptionHandler(AiCapacityExceededException.class)
    public ResponseEntity<Map<String, String>> handle(AiCapacityExceededException error) {
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .body(Map.of("error", "AI_CAPACITY_EXCEEDED"));
    }
}
