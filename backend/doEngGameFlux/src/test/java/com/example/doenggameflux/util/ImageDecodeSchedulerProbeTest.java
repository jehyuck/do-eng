package com.example.doenggameflux.util;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.BufferedWriter;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import reactor.core.publisher.Flux;
import reactor.core.scheduler.Scheduler;
import reactor.core.scheduler.Schedulers;

/**
 * Exp154 test-only probe. It never changes the production decode path.
 */
@Tag("experiment")
@EnabledIfSystemProperty(named = "exp154.enabled", matches = "true")
class ImageDecodeSchedulerProbeTest {

    private static final int[] CONCURRENCIES = {1, 2, 4, 8};
    private static final int WARMUP_BATCHES = 3;
    private static final int MEASURED_BATCHES = 10;
    private static final int BYTES_EXPECTED = 265745;
    private static final String SHA_EXPECTED =
            "1eeadb414471c8f89207118baad01d1a9ec7b05306df0482a79d92d2c615fa99";

    @Test
    void measuresSharedAndDedicatedDecodeSchedulers() throws Exception {
        Path repoRoot = Path.of("..", "..").toAbsolutePath().normalize();
        Path fixture = repoRoot.resolve("image").resolve("arc.jpg");
        assertTrue(Files.isRegularFile(fixture), "fixture not found: " + fixture);

        byte[] source = Files.readAllBytes(fixture);
        String sourceSha = sha256(source);
        assertEquals(BYTES_EXPECTED, source.length);
        assertEquals(SHA_EXPECTED, sourceSha);
        String encoded = Base64.getEncoder().encodeToString(source);
        String payload = "data:image/jpeg;base64," + encoded;

        Path artifactRoot = repoRoot.resolve("experiment").resolve("results")
                .resolve("experiment-1-54");
        Files.createDirectories(artifactRoot);
        writeEnvironment(artifactRoot, repoRoot);
        writeFixture(artifactRoot, source, sourceSha, encoded.length(), payload.length());

        List<Measurement> all = new ArrayList<>();
        List<BatchSummary> batches = new ArrayList<>();
        String[] cells = {"A", "B", "B", "A", "A", "B"};
        String[] runs = {"A1", "B1", "B2", "A2", "A3", "B3"};

        for (int i = 0; i < cells.length; i++) {
            String cell = cells[i];
            String run = runs[i];
            Scheduler scheduler = "A".equals(cell)
                    ? Schedulers.parallel()
                    : Schedulers.newParallel("exp154-decode", Runtime.getRuntime().availableProcessors());
            try {
                for (int concurrency : CONCURRENCIES) {
                    for (int batch = 1; batch <= WARMUP_BATCHES + MEASURED_BATCHES; batch++) {
                        BatchResult result = executeBatch(scheduler, payload, source, sourceSha,
                                cell, run, concurrency, batch);
                        if (batch > WARMUP_BATCHES) {
                            all.addAll(result.measurements);
                            batches.add(new BatchSummary(cell, run, concurrency, batch,
                                    result.wallClockNanos));
                        }
                    }
                }
            } finally {
                if ("B".equals(cell)) {
                    scheduler.dispose();
                }
            }
        }

        writeRaw(artifactRoot.resolve("raw-measurements.csv"), all);
        writeSummary(artifactRoot.resolve("run-summary.json"), all, batches);
        writeComparison(artifactRoot.resolve("comparison.md"), all, batches);
    }

    private BatchResult executeBatch(Scheduler scheduler, String payload, byte[] expected,
            String expectedSha, String cell, String run, int concurrency, int batch) {
        long wallStart = System.nanoTime();
        List<Measurement> measurements = Flux.range(0, concurrency)
                .flatMap(operation -> MonoMeasurement.decode(scheduler, payload, expected,
                        expectedSha, cell, run, concurrency, batch, operation))
                .collectList()
                .block(java.time.Duration.ofSeconds(30));
        long wallClock = System.nanoTime() - wallStart;
        assertEquals(concurrency, measurements.size());
        return new BatchResult(measurements, wallClock);
    }

    private void writeRaw(Path path, List<Measurement> measurements) throws IOException {
        try (BufferedWriter writer = Files.newBufferedWriter(path, StandardCharsets.UTF_8)) {
            writer.write("cell,run,concurrency,batch,operation,startNanos,durationNanos,success,decodedBytes,decodedSha256,threadName\n");
            for (Measurement m : measurements) {
                writer.write(String.format(Locale.ROOT, "%s,%s,%d,%d,%d,%d,%d,%s,%d,%s,%s\n",
                        m.cell, m.run, m.concurrency, m.batch, m.operation, m.startNanos,
                        m.durationNanos, m.success, m.decodedBytes, m.decodedSha256,
                        csv(m.threadName)));
            }
        }
    }

    private void writeSummary(Path path, List<Measurement> measurements,
            List<BatchSummary> batches) throws IOException {
        StringBuilder json = new StringBuilder();
        json.append("{\n  \"experiment\": \"Exp154\",\n  \"generatedAt\": \"")
                .append(Instant.now()).append("\",\n  \"groups\": [\n");
        List<String> groups = new ArrayList<>();
        for (String cell : new String[]{"A", "B"}) {
            for (String run : new String[]{"A1", "B1", "B2", "A2", "A3", "B3"}) {
                if (!run.startsWith(cell)) continue;
                for (int concurrency : CONCURRENCIES) {
                    List<Measurement> group = measurements.stream()
                            .filter(m -> m.cell.equals(cell) && m.run.equals(run)
                                    && m.concurrency == concurrency)
                            .collect(Collectors.toList());
                    if (group.isEmpty()) continue;
                    groups.add(String.format(Locale.ROOT,
                            "    {\"cell\":\"%s\",\"run\":\"%s\",\"concurrency\":%d,\"operationCount\":%d,\"successCount\":%d,\"failureCount\":%d,\"p50Nanos\":%d,\"p95Nanos\":%d,\"maxNanos\":%d,\"throughputOpsPerSec\":%.3f}",
                            cell, run, concurrency, group.size(), successCount(group),
                            group.size() - successCount(group), percentile(group, 50),
                            percentile(group, 95), group.stream().mapToLong(m -> m.durationNanos).max().orElse(0),
                            throughput(group)));
                }
            }
        }
        json.append(String.join(",\n", groups)).append("\n  ],\n  \"batchWallClockMedianNanos\": {\n");
        List<String> batchLines = new ArrayList<>();
        for (String cell : new String[]{"A", "B"}) {
            for (int concurrency : CONCURRENCIES) {
                List<Long> values = batches.stream().filter(b -> b.cell.equals(cell)
                        && b.concurrency == concurrency).map(b -> b.wallClockNanos).sorted()
                        .collect(Collectors.toList());
                if (!values.isEmpty()) {
                    batchLines.add(String.format(Locale.ROOT, "    \"%s-%d\": %d", cell,
                            concurrency, values.get(values.size() / 2)));
                }
            }
        }
        json.append(String.join(",\n", batchLines)).append("\n  }\n}\n");
        Files.writeString(path, json.toString(), StandardCharsets.UTF_8);
    }

    private void writeComparison(Path path, List<Measurement> measurements,
            List<BatchSummary> batches) throws IOException {
        StringBuilder text = new StringBuilder("# Exp154 Comparison\n\n");
        text.append("This artifact reports test-only Base64 decode measurements.\n\n")
                .append("| concurrency | Cell A p95 (ns) | Cell B p95 (ns) | Cell A throughput | Cell B throughput |\n")
                .append("|---:|---:|---:|---:|---:|\n");
        for (int concurrency : CONCURRENCIES) {
            List<Measurement> a = measurements.stream().filter(m -> m.cell.equals("A")
                    && m.concurrency == concurrency).collect(Collectors.toList());
            List<Measurement> b = measurements.stream().filter(m -> m.cell.equals("B")
                    && m.concurrency == concurrency).collect(Collectors.toList());
            text.append(String.format(Locale.ROOT, "| %d | %d | %d | %.3f | %.3f |\n", concurrency,
                    percentile(a, 95), percentile(b, 95), throughput(a), throughput(b)));
        }
        text.append("\nChecksum validation is required for every operation; no production claim is made.\n");
        Files.writeString(path, text.toString(), StandardCharsets.UTF_8);
    }

    private void writeEnvironment(Path root, Path repoRoot) throws IOException {
        String commit = System.getProperty("exp154.sourceCommit", "UNKNOWN");
        try {
            Process process = new ProcessBuilder("git", "-C", repoRoot.toString(), "rev-parse", "HEAD")
                    .redirectErrorStream(true).start();
            String detected = new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8).trim();
            process.waitFor(5, TimeUnit.SECONDS);
            if (detected.matches("[0-9a-fA-F]{40}")) {
                commit = detected;
            }
        } catch (Exception ignored) {
            // Provenance remains explicit when git is unavailable.
        }
        String json = String.format(Locale.ROOT,
                "{\n  \"os\": \"%s\",\n  \"java\": \"%s\",\n  \"jvm\": \"%s\",\n  \"availableProcessors\": %d,\n  \"maxHeapBytes\": %d,\n  \"gradle\": \"test task\",\n  \"sourceCommit\": \"%s\",\n  \"executionTimestamp\": \"%s\"\n}\n",
                esc(System.getProperty("os.name")), esc(System.getProperty("java.version")),
                esc(System.getProperty("java.vm.name")), Runtime.getRuntime().availableProcessors(),
                Runtime.getRuntime().maxMemory(), esc(commit), Instant.now());
        Files.writeString(root.resolve("environment.json"), json, StandardCharsets.UTF_8);
    }

    private void writeFixture(Path root, byte[] source, String sha,
            int base64Length, int dataUrlLength)
            throws IOException {
        String json = String.format(Locale.ROOT,
                "{\n  \"path\": \"%s\",\n  \"bytes\": %d,\n  \"base64Length\": %d,\n  \"dataUrlLength\": %d,\n  \"sha256\": \"%s\"\n}\n",
                "image/arc.jpg", source.length, base64Length, dataUrlLength, sha);
        Files.writeString(root.resolve("fixture-fingerprint.json"), json, StandardCharsets.UTF_8);
    }

    private static int successCount(List<Measurement> values) {
        return (int) values.stream().filter(m -> m.success).count();
    }

    private static long percentile(List<Measurement> values, int percentile) {
        if (values.isEmpty()) return 0;
        List<Long> sorted = values.stream().map(m -> m.durationNanos).sorted().collect(Collectors.toList());
        int index = Math.min(sorted.size() - 1, Math.max(0,
                (int) Math.ceil(percentile / 100.0 * sorted.size()) - 1));
        return sorted.get(index);
    }

    private static double throughput(List<Measurement> values) {
        if (values.isEmpty()) return 0;
        long min = values.stream().mapToLong(m -> m.startNanos).min().orElse(0);
        long max = values.stream().mapToLong(m -> m.startNanos + m.durationNanos).max().orElse(min);
        return (max <= min) ? 0 : values.size() / ((max - min) / 1_000_000_000.0);
    }

    private static String sha256(byte[] bytes) throws NoSuchAlgorithmException {
        byte[] digest = MessageDigest.getInstance("SHA-256").digest(bytes);
        StringBuilder result = new StringBuilder();
        for (byte value : digest) result.append(String.format(Locale.ROOT, "%02x", value));
        return result.toString();
    }

    private static String csv(String value) {
        return value == null ? "" : value.replace(",", "_");
    }

    private static String esc(String value) {
        return value.replace("\\", "\\\\").replace("\"", "\\\"");
    }

    private static final class MonoMeasurement {
        private static reactor.core.publisher.Mono<Measurement> decode(Scheduler scheduler, String payload,
                byte[] expected, String expectedSha, String cell, String run, int concurrency, int batch,
                int operation) {
            return reactor.core.publisher.Mono.fromCallable(() -> {
                long start = System.nanoTime();
                byte[] decoded = ImagePayloadDecoder.decodeDataUrlOrBase64(payload);
                String sha = sha256(decoded);
                return new Measurement(cell, run, concurrency, batch, operation, start,
                        System.nanoTime() - start, decoded.length == expected.length && sha.equals(expectedSha),
                        decoded.length, sha, Thread.currentThread().getName());
            }).subscribeOn(scheduler);
        }
    }

    private static final class BatchResult {
        private final List<Measurement> measurements;
        private final long wallClockNanos;

        private BatchResult(List<Measurement> measurements, long wallClockNanos) {
            this.measurements = measurements;
            this.wallClockNanos = wallClockNanos;
        }
    }

    private static final class BatchSummary {
        private final String cell;
        private final String run;
        private final int concurrency;
        private final int batch;
        private final long wallClockNanos;

        private BatchSummary(String cell, String run, int concurrency, int batch, long wallClockNanos) {
            this.cell = cell;
            this.run = run;
            this.concurrency = concurrency;
            this.batch = batch;
            this.wallClockNanos = wallClockNanos;
        }
    }

    private static final class Measurement {
        private final String cell;
        private final String run;
        private final int concurrency;
        private final int batch;
        private final int operation;
        private final long startNanos;
        private final long durationNanos;
        private final boolean success;
        private final int decodedBytes;
        private final String decodedSha256;
        private final String threadName;

        private Measurement(String cell, String run, int concurrency, int batch, int operation,
                long startNanos, long durationNanos, boolean success, int decodedBytes,
                String decodedSha256, String threadName) {
            this.cell = cell;
            this.run = run;
            this.concurrency = concurrency;
            this.batch = batch;
            this.operation = operation;
            this.startNanos = startNanos;
            this.durationNanos = durationNanos;
            this.success = success;
            this.decodedBytes = decodedBytes;
            this.decodedSha256 = decodedSha256;
            this.threadName = threadName;
        }
    }
}
