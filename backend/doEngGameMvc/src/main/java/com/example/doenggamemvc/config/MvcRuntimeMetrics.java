package com.example.doenggamemvc.config;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.binder.MeterBinder;
import java.lang.reflect.Method;
import java.util.concurrent.Executor;
import org.apache.coyote.ProtocolHandler;
import org.apache.http.impl.conn.PoolingHttpClientConnectionManager;
import org.apache.http.pool.PoolStats;
import org.apache.catalina.connector.Connector;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.web.embedded.tomcat.TomcatServletWebServerFactory;
import org.springframework.boot.web.server.WebServerFactoryCustomizer;
import org.springframework.stereotype.Component;

/**
 * Experiment-only gauges. The request executor is read from the running
 * Tomcat connector rather than from JVM-wide thread counters.
 */
@Component
@ConditionalOnProperty(
        name = "doeng.experiment.metrics.enabled",
        havingValue = "true")
public class MvcRuntimeMetrics implements
        MeterBinder,
        WebServerFactoryCustomizer<TomcatServletWebServerFactory> {

    private final PoolingHttpClientConnectionManager connectionManager;
    private volatile Connector connector;

    public MvcRuntimeMetrics(
            PoolingHttpClientConnectionManager connectionManager) {
        this.connectionManager = connectionManager;
    }

    @Override
    public void customize(TomcatServletWebServerFactory factory) {
        factory.addConnectorCustomizers(value -> connector = value);
    }

    @Override
    public void bindTo(MeterRegistry registry) {
        Gauge.builder("doeng.mvc.request_threads.busy", this,
                source -> source.executorNumber("getActiveCount"))
                .description("Active threads in the Tomcat request executor")
                .register(registry);
        Gauge.builder("doeng.mvc.request_threads.max", this,
                source -> source.executorNumber(
                        "getMaximumPoolSize", "getMaxThreads"))
                .description("Maximum threads in the Tomcat request executor")
                .register(registry);
        Gauge.builder("doeng.mvc.request_threads.queue_size", this,
                MvcRuntimeMetrics::executorQueueSize)
                .description("Queued tasks in the Tomcat request executor")
                .register(registry);

        Gauge.builder("doeng.mvc.external_http.leased", this,
                source -> source.poolStats().getLeased())
                .description("Leased Apache HttpClient connections")
                .register(registry);
        Gauge.builder("doeng.mvc.external_http.available", this,
                source -> source.poolStats().getAvailable())
                .description("Available Apache HttpClient connections")
                .register(registry);
        Gauge.builder("doeng.mvc.external_http.pending", this,
                source -> source.poolStats().getPending())
                .description("Requests pending Apache HttpClient connection lease")
                .register(registry);
        Gauge.builder("doeng.mvc.external_http.max", this,
                source -> source.poolStats().getMax())
                .description("Maximum Apache HttpClient connections")
                .register(registry);
    }

    private PoolStats poolStats() {
        return connectionManager.getTotalStats();
    }

    private double executorNumber(String... methodNames) {
        Object executor = requestExecutor();
        if (executor == null) {
            return 0;
        }
        for (String methodName : methodNames) {
            Object value = invoke(executor, methodName);
            if (value instanceof Number) {
                return ((Number) value).doubleValue();
            }
        }
        return 0;
    }

    private double executorQueueSize() {
        Object executor = requestExecutor();
        Object queue = executor == null ? null : invoke(executor, "getQueue");
        Object size = queue == null ? null : invoke(queue, "size");
        return size instanceof Number ? ((Number) size).doubleValue() : 0;
    }

    private Object requestExecutor() {
        Connector currentConnector = connector;
        if (currentConnector == null) {
            return null;
        }
        ProtocolHandler handler = currentConnector.getProtocolHandler();
        Executor executor = handler == null ? null : handler.getExecutor();
        return executor;
    }

    private Object invoke(Object target, String methodName) {
        try {
            Method method = target.getClass().getMethod(methodName);
            return method.invoke(target);
        } catch (ReflectiveOperationException ignored) {
            return null;
        }
    }
}
