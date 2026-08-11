package com.example.doenggamemvc.experiment;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

class ExperimentRequestTraceContextTest {

    @AfterEach
    void clearContext() {
        ExperimentRequestTraceContext.clear();
    }

    @Test
    void samplingIsDeterministicAndOneInSixtyFourShape() {
        String sampled = null;
        String unsampled = null;
        for (int i = 0; i < 1000 && (sampled == null || unsampled == null); i++) {
            String candidate = "I1S-AI1S-test-u" + i;
            if (ExperimentRequestTraceContext.shouldSample(candidate)) {
                sampled = candidate;
            } else {
                unsampled = candidate;
            }
        }

        assertNotNull(sampled);
        assertNotNull(unsampled);
        assertTrue(ExperimentRequestTraceContext.shouldSample(sampled));
        assertTrue(ExperimentRequestTraceContext.shouldSample(sampled));
        assertFalse(ExperimentRequestTraceContext.shouldSample(unsampled));
        assertFalse(ExperimentRequestTraceContext.shouldSample(null));
        assertFalse(ExperimentRequestTraceContext.shouldSample(""));
    }

    @Test
    void contextKeepsRequestIdentityAndCanBeRemoved() {
        ExperimentRequestTraceContext.TraceState installed =
                ExperimentRequestTraceContext.install("run", "request", "mission");

        assertSame(installed, ExperimentRequestTraceContext.current());
        assertTrue("request".equals(installed.getRequestId()));
        assertTrue("mission".equals(installed.getMissionRunId()));

        ExperimentRequestTraceContext.clear();
        assertTrue(ExperimentRequestTraceContext.current() == null);
    }
}
