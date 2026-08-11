# MVC I1S-AI1S JFR Root-Cause Diagnostic — JFR002

## Run and validity

`I1S-AI1S-MVC-JFR002` ran once with the frozen `comparison-vu160-service-1s-ai1000ms.json` configuration at Git HEAD `d6d5283fc348ba595e3e64305fd69e339d2c3430`. No WebFlux run, tuning, configuration change, or production-code change was performed.

The explicit-stop lifecycle completed successfully:

- `JFR.start` succeeded.
- `JFR.stop` succeeded with the container filename.
- source bytes: 48,331,364.
- copied bytes: 48,331,364.
- `jfr summary` succeeded.
- `jfr-validation.json.valid = true`.
- raw JFR SHA-256: `3016C3305D386BF9D78477DD4E45D39BA7E0268787751352F6EA73823D1676DF`.

The runner produced `verification-summary.json` with `executionValidity=VALID`. The application outcome was unsuccessful and is preserved as an application result, not as an execution failure.

## Client result

```text
started: 16532
completed: 16532
http200: 0
timeout: 16532
connectionError: 0
successfulRps: 0
totalRps: 157.44761904761904
maxInFlight: 1600
```

## JFR evidence

The 2,346 `jdk.ExecutionSample` events show the strongest sampled activity in:

1. Jackson JSON serialization/deserialization (`UTF8JsonGenerator`, `MapSerializer`, `StringDeserializer`).
2. Base64/image processing (`Base64$Decoder.decode`, `ImagePayloadDecoder.decodeDataUrlOrBase64`).
3. MVC request handling (`MissionController.requestFaceAi`).
4. Blocking outbound HTTP (`Apache HttpClient MainClientExec/ProtocolExec/RetryExec`, Spring `RestTemplate`).

The recording summary contains 60,054 `jdk.SocketRead` events. This supports blocking socket-response activity in the outbound path. It does not uniquely prove HTTP connection-acquire waiting; therefore `HTTP_POOL_WAIT_TYPE` is `SOCKET_RESPONSE_WAIT` supported, with connection-acquire separation not established.

Tomcat executor threads frequently parked on `ReentrantLock$NonfairSync`. The JFR stack depth reached AQS park/acquire frames without exposing a unique owning application lock, so the exact lock site is not identified.

GC evidence supports pressure but not a sole cause: 637 `jdk.GarbageCollection` events, approximately 52,244.99 ms aggregate duration, maximum approximately 2,141.09 ms, with 49 events at least 100 ms and 36 at least 500 ms. Allocation events were also numerous, and the sampled allocation path was concentrated in JSON and Base64/image processing.

## Attribution

```text
TRIGGER:
request-side JSON/Base64 CPU and allocation work

AMPLIFIER:
blocking outbound HTTP activity holding MVC request workers

FINAL_COLLAPSE_STATE:
multiple coupled pressures; a single final resource boundary is not isolated

CURRENT_PRIMARY_BOTTLENECK:
MULTIPLE_COUPLED

CURRENT_ROOT_CAUSE_CONFIDENCE:
MEDIUM

DATABASE_PRIMARY_CAUSE:
NOT_SUPPORTED

HISTORICAL_DISCREPANCY:
STILL_UNEXPLAINED
```

The historical `RUN-20260731-252` has no equivalent JFR timeline in the available evidence. This JFR002 recording therefore explains the current MVC execution path only and does not explain the historical discrepancy.

```text
TUNING_EXECUTED: NO
WEBFLUX_EXECUTED: NO
PRODUCTION_CODE_CHANGED: NO
```
