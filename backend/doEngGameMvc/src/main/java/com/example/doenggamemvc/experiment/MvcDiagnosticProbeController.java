package com.example.doenggamemvc.experiment;

import com.example.doenggamemvc.dto.ImageRequest;
import java.util.Map;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Profile("experiment")
@RestController
@RequestMapping("/experiment/mvc-probe")
public class MvcDiagnosticProbeController {

    private final MvcDiagnosticProbeService service;

    public MvcDiagnosticProbeController(MvcDiagnosticProbeService service) {
        this.service = service;
    }

    @PostMapping
    public ResponseEntity<Map<String, Object>> probe(
            @RequestBody ImageRequest request,
            @RequestParam(defaultValue = "INGRESS") String mode,
            @RequestParam(defaultValue = "happy") String answer,
            @RequestParam(defaultValue = "diagnostic") String runId,
            @RequestHeader(value = HttpHeaders.AUTHORIZATION, required = false)
            String authorization,
            @RequestHeader(value = "X-Experiment-Request-Id", required = false)
            String requestId) {
        return ResponseEntity.ok(service.probe(
                mode,
                request.getImage(),
                answer,
                authorization,
                runId,
                requestId));
    }
}
