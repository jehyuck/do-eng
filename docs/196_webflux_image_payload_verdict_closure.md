# WebFlux image payload material verdict 종결

## 1. 목적

`WEBFLUX-IMAGE-PAYLOAD-PROFILE-002`의 기존 JFR만 read-only로 다시 집계하여, 사전에 정의한 image payload material-cost candidate Gate를 최종 판정한다.

새 workload, JFR 재수집, production source 변경은 수행하지 않았다.

## 2. Evidence

- Experiment source HEAD: `407e380f0fdb91a167685ebc8300b544039b3d75`
- Run ID: `WEBFLUX-IMAGE-PAYLOAD-PROFILE-002`
- Characterization document: `docs/194_webflux_image_payload_characterization.md`
- Raw Evidence package: [Google Drive package](https://drive.google.com/file/d/1feo1eQ5PHwAexUyyb5b9751SDPw0cYJv/view)
- Raw Evidence manifest: [Google Drive manifest](https://drive.google.com/file/d/1psdM__CT2WUK3kY2bGR08XTOBk5acGm2/view)
- Package SHA-256: `2edaa463aed21f38848b41abbed1b5a8f12d628a35deaeda06ed23fd89d6bf72`
- JFR: `jvm-recording.jfr`
- JFR SHA-256: `cc8cb206a5bd9a9113ce3e49c9435c443e11079aa8a2f245465833ee7b2bc75f`

## 3. 사전 정의 Gate

최종 classification은 다음 중 하나다.

- A — `PAYLOAD_COST_MATERIAL_CANDIDATE`
- B — `PAYLOAD_COST_VISIBLE_BUT_LOW`
- C — `PAYLOAD_COST_NOT_SUPPORTED`
- D — `PROFILE_INCONCLUSIVE`

A는 다음 CPU 또는 allocation 조건과 time-window consistency를 만족할 때만 허용한다.

### CPU Gate

payload 관련 CPU stack family가 CPU top 5에 포함되고 total `jdk.ExecutionSample`의 `>= 5%`를 차지하는 조건이 최소 2개 measurement window에서 반복된다.

### Allocation Gate

payload 관련 allocation family가 allocation top 3이거나 sampled allocation weight의 `>= 10%`를 차지하는 조건이 최소 2개 measurement window에서 반복된다.

이 threshold는 이번 candidate-selection을 위한 내부 Gate이며 일반적인 industry threshold가 아니다.

## 4. Measurement window

Raw client progress에서 load 시작은 `2026-08-13T09:20:49.818Z`, load-stop은 `2026-08-13T09:22:34.831Z`로 확인됐다.

105초 measurement 구간을 35초씩 3개 window로 나눴다.

| Window | 구간 | `jdk.ExecutionSample` denominator |
|---|---|---:|
| Early | 09:20:49.818Z ~ 09:21:24.818Z | 1,195 |
| Middle | 09:21:24.818Z ~ 09:21:59.818Z | 1,042 |
| Late | 09:21:59.818Z ~ 09:22:34.818Z | 1,092 |

Measurement 구간 내 CPU sample은 총 3,329건이다. JFR 전체의 `jdk.ExecutionSample`은 3,353건이며 measurement 바깥 24건은 denominator에서 제외했다.

## 5. CPU Gate 결과

### Early

CPU top 5 안에서 다음 Jackson JSON payload 관련 method가 5%를 넘었다.

- `UTF8JsonGenerator::_writeStringSegment`: `150 / 1,195 = 12.55%`
- `UTF8StreamJsonParser::_finishString2`: `135 / 1,195 = 11.30%`

### Middle

- `UTF8JsonGenerator::_writeStringSegments`: `138 / 1,042 = 13.24%`
- `UTF8StreamJsonParser::_finishString2`: `86 / 1,042 = 8.25%`
- `UTF8StreamJsonParser::_skipString`: `54 / 1,042 = 5.18%`

### Late

- `UTF8JsonGenerator::_writeStringSegments`: `109 / 1,092 = 9.98%`
- `UTF8StreamJsonParser::_finishString2`: `79 / 1,092 = 7.23%`
- `Base64$Decoder::decode0`: `60 / 1,092 = 5.49%`

따라서 CPU Gate는 최소 2개가 아니라 **3개 window 모두에서 충족**됐다.

stack 내에서 가장 가까운 payload-specific family를 하나만 선택하는 unique attribution으로 다시 집계해도 Jackson JSON family는 다음 비중으로 반복됐다.

- Early: `688 / 1,195 = 57.57%`
- Middle: `363 / 1,042 = 34.84%`
- Late: `306 / 1,092 = 28.02%`

이 family 비중은 candidate-selection을 보조하는 값이며, Jackson 전체 비용이 모두 image payload만의 인과라고 해석하지 않는다.

## 6. Allocation 관찰

Allocation은 CPU Gate 판정의 필수 근거로 사용하지 않았다. CPU Gate만으로 이미 A 조건이 충족됐기 때문이다.

다만 JFR의 `ObjectAllocationInNewTLAB`에서는 `tlabSize`, `ObjectAllocationOutsideTLAB`에서는 `allocationSize`를 사용한 event-weight 추정에서도 동일한 방향이 반복됐다.

Jackson JSON stack family의 estimated allocation weight 비중:

- Early: `75.91%`
- Middle: `60.98%`
- Late: `57.49%`

Jackson `TextBuffer::carr`도 estimated allocation weight 기준 각 window에서 상위권에 반복됐다.

이 값은 JFR allocation event를 이용한 추정 weight이며 전체 heap allocation byte의 정확한 합계로 해석하지 않는다.

## 7. 최종 판정

```text
PROFILE VALID
VERDICT CLOSED
CLASSIFICATION = PAYLOAD_COST_MATERIAL_CANDIDATE
```

사전 정의한 CPU Gate가 3개 measurement window 모두에서 충족되므로 A로 종결한다.

## 8. 이 판정이 의미하는 것

확인된 범위는 좁다.

> 현재 WebFlux full-path 실행에서 JSON/Base64/image payload representation 및 처리 비용은 동일 자원 내 software-headroom을 검토할 가치가 있는 material-cost candidate다.

이 판정은 다음을 의미하지 않는다.

- payload processing이 MVC collapse의 root cause라는 뜻이 아니다.
- Jackson, Base64, Netty, image decoding 중 하나가 단독 root cause라는 뜻이 아니다.
- payload 최적화가 실제 throughput 또는 latency를 개선한다는 뜻이 아니다.
- 1초 cadence degradation의 단일 원인이 payload라는 뜻이 아니다.
- WebFlux가 MVC보다 일반적으로 우수하다는 뜻이 아니다.

## 9. 다음 단계 Gate

새로운 성능 Claim은 아직 없다.

다음 단계로 진행하려면 payload representation/serialization 비용만 하나의 변인으로 줄이는 narrow controlled A/B를 별도로 설계해야 한다.

동일 source/runtime/resource/request/downstream contract를 유지하고, 변경 전후의 CPU/allocation과 service outcome을 함께 비교해야 한다.

해당 controlled A/B가 승인·수행되기 전에는 optimization effect를 주장하지 않는다.
