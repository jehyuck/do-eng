package com.example.doenggamemvc.experiment;

/** Request-local experiment trace state. Never created outside the experiment profile. */
public final class ExperimentRequestTraceContext {

    private static final ThreadLocal<TraceState> CURRENT = new ThreadLocal<>();

    private ExperimentRequestTraceContext() {
    }

    public static TraceState install(
            String runId,
            String requestId,
            String missionRunId) {
        TraceState state = new TraceState(
                runId,
                requestId,
                missionRunId,
                System.nanoTime(),
                shouldSample(requestId));
        CURRENT.set(state);
        return state;
    }

    public static TraceState current() {
        return CURRENT.get();
    }

    public static void clear() {
        CURRENT.remove();
    }

    static boolean shouldSample(String requestId) {
        if (requestId == null || requestId.isBlank()) {
            return false;
        }
        return Math.floorMod(requestId.hashCode(), 64) == 0;
    }

    public static final class TraceState {
        private final String runId;
        private final String requestId;
        private final String missionRunId;
        private final long serverEnteredAtNs;
        private final boolean sampled;

        private TraceState(
                String runId,
                String requestId,
                String missionRunId,
                long serverEnteredAtNs,
                boolean sampled) {
            this.runId = runId;
            this.requestId = requestId;
            this.missionRunId = missionRunId;
            this.serverEnteredAtNs = serverEnteredAtNs;
            this.sampled = sampled;
        }

        public String getRunId() {
            return runId;
        }

        public String getRequestId() {
            return requestId;
        }

        public String getMissionRunId() {
            return missionRunId;
        }

        public long getServerEnteredAtNs() {
            return serverEnteredAtNs;
        }

        public boolean isSampled() {
            return sampled;
        }
    }
}
