package com.example.doenggameflux.component;

import java.util.Objects;
import org.springframework.http.HttpHeaders;
import reactor.util.context.Context;
import reactor.util.context.ContextView;

/** Request-scoped diagnostic identity carried only through Reactor Context and headers. */
public final class RequestIdentity {

    public static final String EXPERIMENT_REQUEST_ID_KEY = "experimentRequestId";
    public static final String EXPERIMENT_RUN_ID_KEY = "experimentRunId";
    public static final String MISSION_RUN_ID_KEY = "missionRunId";

    public static final String EXPERIMENT_REQUEST_ID_HEADER = "X-Experiment-Request-Id";
    public static final String EXPERIMENT_RUN_ID_HEADER = "X-Experiment-Run-Id";
    public static final String MISSION_RUN_ID_HEADER = "X-Mission-Run-Id";

    private final String experimentRequestId;
    private final String experimentRunId;
    private final String missionRunId;

    public RequestIdentity(String experimentRequestId, String experimentRunId, String missionRunId) {
        this.experimentRequestId = normalize(experimentRequestId);
        this.experimentRunId = normalize(experimentRunId);
        this.missionRunId = normalize(missionRunId);
    }

    public static RequestIdentity fromHeaders(HttpHeaders headers) {
        return new RequestIdentity(
                headers.getFirst(EXPERIMENT_REQUEST_ID_HEADER),
                headers.getFirst(EXPERIMENT_RUN_ID_HEADER),
                headers.getFirst(MISSION_RUN_ID_HEADER));
    }

    public static RequestIdentity from(ContextView contextView) {
        return new RequestIdentity(
                contextView.getOrDefault(EXPERIMENT_REQUEST_ID_KEY, null),
                contextView.getOrDefault(EXPERIMENT_RUN_ID_KEY, null),
                contextView.getOrDefault(MISSION_RUN_ID_KEY, null));
    }

    public Context writeTo(Context context) {
        Context next = context;
        if (experimentRequestId != null) next = next.put(EXPERIMENT_REQUEST_ID_KEY, experimentRequestId);
        if (experimentRunId != null) next = next.put(EXPERIMENT_RUN_ID_KEY, experimentRunId);
        if (missionRunId != null) next = next.put(MISSION_RUN_ID_KEY, missionRunId);
        return next;
    }

    public boolean hasExperimentRequestId() {
        return experimentRequestId != null;
    }

    public String getExperimentRequestId() {
        return experimentRequestId;
    }

    public String getExperimentRunId() {
        return experimentRunId;
    }

    public String getMissionRunId() {
        return missionRunId;
    }

    private static String normalize(String value) {
        if (value == null || value.isBlank()) return null;
        return value;
    }

    @Override
    public boolean equals(Object other) {
        if (this == other) return true;
        if (!(other instanceof RequestIdentity)) return false;
        RequestIdentity that = (RequestIdentity) other;
        return Objects.equals(experimentRequestId, that.experimentRequestId)
                && Objects.equals(experimentRunId, that.experimentRunId)
                && Objects.equals(missionRunId, that.missionRunId);
    }

    @Override
    public int hashCode() {
        return Objects.hash(experimentRequestId, experimentRunId, missionRunId);
    }
}
