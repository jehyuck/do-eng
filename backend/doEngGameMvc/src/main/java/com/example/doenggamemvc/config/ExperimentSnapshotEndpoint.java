package com.example.doenggamemvc.config;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import java.lang.management.ManagementFactory;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import org.springframework.boot.actuate.endpoint.annotation.Endpoint;
import org.springframework.boot.actuate.endpoint.annotation.ReadOperation;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

/**
 * One low-cost experiment snapshot. It replaces multiple per-meter HTTP
 * requests and intentionally exposes only the values used by the experiment.
 */
@Component
@Endpoint(id = "doengexperiment")
@ConditionalOnProperty(
        name = "doeng.experiment.metrics.enabled",
        havingValue = "true")
public class ExperimentSnapshotEndpoint {

    private final MeterRegistry registry;

    public ExperimentSnapshotEndpoint(MeterRegistry registry) {
        this.registry = registry;
    }

    @ReadOperation
    public Map<String, Object> snapshot() {
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("capturedAtEpochMs", System.currentTimeMillis());
        response.put("implementation", "mvc");
        response.put("jvm", jvmSnapshot());
        response.put("requestRuntime", requestRuntimeSnapshot());
        response.put("outboundHttp", outboundHttpSnapshot());
        response.put("databasePool", databasePoolSnapshot());
        return response;
    }

    private Map<String, Object> jvmSnapshot() {
        Map<String, Object> values = new LinkedHashMap<>();
        values.put(
                "heapUsedBytes",
                ManagementFactory.getMemoryMXBean().getHeapMemoryUsage().getUsed());
        values.put(
                "liveThreads",
                ManagementFactory.getThreadMXBean().getThreadCount());
        values.put("processCpuUsage", gaugeSum("process.cpu.usage"));

        Collection<Timer> pauses = registry.find("jvm.gc.pause").timers();
        long count = 0;
        double totalMs = 0;
        double maxMs = 0;
        for (Timer pause : pauses) {
            count += pause.count();
            totalMs += pause.totalTime(TimeUnit.MILLISECONDS);
            maxMs = Math.max(
                    maxMs,
                    pause.max(TimeUnit.MILLISECONDS));
        }
        values.put("gcPauseCount", count);
        values.put("gcPauseTotalMs", totalMs);
        values.put("gcPauseMaxMs", maxMs);
        return values;
    }

    private Map<String, Object> requestRuntimeSnapshot() {
        Map<String, Object> values = new LinkedHashMap<>();
        values.put("type", "tomcat-worker");
        values.put(
                "busy",
                gaugeSum("doeng.mvc.request_threads.busy"));
        values.put(
                "max",
                gaugeSum("doeng.mvc.request_threads.max"));
        values.put(
                "queue",
                gaugeSum("doeng.mvc.request_threads.queue_size"));
        return values;
    }

    private Map<String, Object> outboundHttpSnapshot() {
        Map<String, Object> values = new LinkedHashMap<>();
        values.put(
                "active",
                gaugeSum("doeng.mvc.external_http.leased"));
        values.put(
                "pending",
                gaugeSum("doeng.mvc.external_http.pending"));
        values.put(
                "max",
                gaugeSum("doeng.mvc.external_http.max"));
        return values;
    }

    private Map<String, Object> databasePoolSnapshot() {
        Map<String, Object> values = new LinkedHashMap<>();
        values.put(
                "active",
                gaugeSum("hikaricp.connections.active"));
        values.put(
                "pending",
                gaugeSum("hikaricp.connections.pending"));
        values.put(
                "max",
                gaugeSum("hikaricp.connections.max"));
        return values;
    }

    private Double gaugeSum(String name) {
        Collection<Gauge> gauges = registry.find(name).gauges();
        if (gauges.isEmpty()) {
            return null;
        }
        double sum = 0;
        boolean found = false;
        for (Gauge gauge : gauges) {
            double value = gauge.value();
            if (Double.isFinite(value)) {
                sum += value;
                found = true;
            }
        }
        return found ? sum : null;
    }
}
