package com.example.doenggameflux.component;

import com.example.doenggameflux.dispatcher.AbstractSinkDispatcher;
import com.example.doenggameflux.dispatcher.DispatcherMetrics;
import com.example.doenggameflux.dispatcher.DispatcherSpec;
import com.example.doenggameflux.dispatcher.MissionExecutionContext;
import com.example.doenggameflux.dto.response.AiDecisionResultDto;
import java.util.HashMap;
import java.util.Map;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

@Component
public final class AiDispatcher extends AbstractSinkDispatcher<AiDispatchRequest, AiDecisionResultDto> {

    private final WebClient aiWebClient;

    public AiDispatcher(
            @Qualifier("aiWebClient") WebClient aiWebClient,
            DispatcherMetrics metrics,
            @Value("${doeng.dispatcher.ai.concurrency:400}") int concurrency,
            @Value("${doeng.dispatcher.ai.queue-capacity:4000}") int queueCapacity) {
        super(new DispatcherSpec("ai", concurrency, queueCapacity), metrics);
        this.aiWebClient = aiWebClient;
    }

    @Override
    protected Mono<AiDecisionResultDto> invoke(
            MissionExecutionContext context,
            AiDispatchRequest input) {
        Map<String, String> request = new HashMap<>();
        request.put("answer", input.getAnswer());
        request.put("image", input.getImage().getImage());

        WebClient.RequestBodySpec requestSpec = aiWebClient.post()
                .uri(input.getAiPath())
                .contentType(MediaType.APPLICATION_JSON)
                .accept(MediaType.APPLICATION_JSON);
        RequestIdentity identity = input.getRequestIdentity();
        if (identity.hasExperimentRequestId()) {
            requestSpec.headers(headers -> {
                headers.set(RequestIdentity.EXPERIMENT_REQUEST_ID_HEADER,
                        identity.getExperimentRequestId());
                if (identity.getExperimentRunId() != null) {
                    headers.set(RequestIdentity.EXPERIMENT_RUN_ID_HEADER,
                            identity.getExperimentRunId());
                }
                if (identity.getMissionRunId() != null) {
                    headers.set(RequestIdentity.MISSION_RUN_ID_HEADER,
                            identity.getMissionRunId());
                }
            });
        }

        return requestSpec
                .bodyValue(request)
                .retrieve()
                .bodyToMono(AiDecisionResultDto.class);
    }
}
