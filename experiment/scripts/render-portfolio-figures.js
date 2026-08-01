const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..', '..');
const outputDir = path.join(root, 'docs', 'portfolio-figures');

function readSummary(runId) {
  const text = fs.readFileSync(
    path.join(root, 'experiment', 'results', runId, 'client-summary.stdout.json'),
    'utf8',
  ).replace(/^\uFEFF/, '');
  return JSON.parse(text);
}

function escapeXml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function writeSvg(filename, content) {
  fs.mkdirSync(outputDir, { recursive: true });
  fs.writeFileSync(path.join(outputDir, filename), content, 'utf8');
}

function svgShell(title, body) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="700" viewBox="0 0 1200 700" role="img" aria-labelledby="title desc">
  <title id="title">${escapeXml(title)}</title>
  <desc id="desc">Do-Eng WebFlux와 MVC 부하 실험의 원시 결과를 요약한 그래프</desc>
  <style>
    text { font-family: Pretendard, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; fill: #172033; }
    .title { font-size: 30px; font-weight: 700; }
    .subtitle { font-size: 16px; fill: #526174; }
    .label { font-size: 17px; font-weight: 600; }
    .small { font-size: 14px; fill: #526174; }
    .value { font-size: 18px; font-weight: 700; }
    .axis { stroke: #cbd5e1; stroke-width: 1; }
    .grid { stroke: #e2e8f0; stroke-width: 1; }
    .note { font-size: 13px; fill: #64748b; }
  </style>
  <rect width="1200" height="700" fill="#ffffff"/>
  ${body}
</svg>`;
}

function coreComparison() {
  const flux = readSummary('RUN-20260729-155');
  const mvc = readSummary('RUN-20260729-156');
  const rows = [
    { label: 'WebFlux', run: 'RUN-155', success: 100, p95: flux.latencyMs.p95, color: '#2563eb' },
    { label: 'MVC (worker 200)', run: 'RUN-156', success: (mvc.successfulRequests / mvc.completedRequests) * 100, p95: mvc.latencyMs.p95, color: '#dc2626' },
  ];
  const left = 90;
  const successX = 90;
  const latencyX = 650;
  const width = 430;
  const successY = [235, 370];
  const latencyY = [235, 370];
  const successTicks = [0, 25, 50, 75, 100];
  const latencyTicks = [0, 2500, 5000, 7500, 10000];
  const marks = [];
  marks.push(`<text x="${left}" y="64" class="title">핵심 비교: AI 2초 · VU 120</text>`);
  marks.push(`<text x="${left}" y="94" class="subtitle">동일 이미지·외부 I/O mock·DB 저장 조건 / 두 실행 모두 정합성·monitor 통과</text>`);
  marks.push(`<text x="${successX}" y="150" class="label">성공률 (%)</text>`);
  marks.push(`<text x="${latencyX}" y="150" class="label">p95 판정 응답시간 (ms)</text>`);
  for (const tick of successTicks) {
    const x = successX + (tick / 100) * width;
    marks.push(`<line x1="${x}" y1="175" x2="${x}" y2="455" class="grid"/>`);
    marks.push(`<text x="${x}" y="482" class="small" text-anchor="middle">${tick}</text>`);
  }
  for (const tick of latencyTicks) {
    const x = latencyX + (tick / 10000) * width;
    marks.push(`<line x1="${x}" y1="175" x2="${x}" y2="455" class="grid"/>`);
    marks.push(`<text x="${x}" y="482" class="small" text-anchor="middle">${tick.toLocaleString()}</text>`);
  }
  rows.forEach((row, index) => {
    const y = successY[index];
    marks.push(`<text x="${successX}" y="${y - 18}" class="label">${escapeXml(row.label)} <tspan class="small">${row.run}</tspan></text>`);
    marks.push(`<rect x="${successX}" y="${y}" width="${width}" height="44" rx="5" fill="#e2e8f0"/>`);
    marks.push(`<rect x="${successX}" y="${y}" width="${(row.success / 100) * width}" height="44" rx="5" fill="${row.color}"/>`);
    marks.push(`<text x="${successX + width + 12}" y="${y + 29}" class="value">${row.success.toFixed(2)}%</text>`);
    const ly = latencyY[index];
    marks.push(`<rect x="${latencyX}" y="${ly}" width="${width}" height="44" rx="5" fill="#e2e8f0"/>`);
    marks.push(`<rect x="${latencyX}" y="${ly}" width="${Math.min(row.p95, 10000) / 10000 * width}" height="44" rx="5" fill="${row.color}"/>`);
    marks.push(`<text x="${latencyX + width + 12}" y="${ly + 29}" class="value">${row.p95.toLocaleString()} ms</text>`);
  });
  marks.push(`<line x1="${left}" y1="535" x2="1110" y2="535" class="axis"/>`);
  marks.push(`<text x="${left}" y="572" class="label">관찰</text>`);
  marks.push(`<text x="${left + 75}" y="572" class="subtitle">MVC는 Tomcat busy 200/200, queue 최대 2,345, outbound HTTP active 200과 함께 오류율 61.93%를 기록했다.</text>`);
  marks.push(`<text x="${left}" y="613" class="note">해석: 이 조건에서 WebFlux가 일반적으로 더 빠르다는 뜻이 아니라, 외부 I/O 동시성이 큰 현재 이미지 미션 체인에서 성공률과 tail latency를 유지한 유효 비교 근거다.</text>`);
  return svgShell('AI 2초 VU 120 WebFlux MVC 핵심 비교', marks.join('\n  '));
}

function freshnessAndTuning() {
  const flux = readSummary('RUN-20260731-166');
  const mvc200 = readSummary('RUN-20260731-167');
  const mvc400a = readSummary('RUN-20260731-169');
  const mvc400b = readSummary('RUN-20260731-170');
  const rows = [
    { label: 'WebFlux', run: 'RUN-166', p95: flux.latencyMs.p95, p99: flux.latencyMs.p99, color: '#2563eb', status: '유효' },
    { label: 'MVC worker 200', run: 'RUN-167', p95: mvc200.latencyMs.p95, p99: mvc200.latencyMs.p99, color: '#dc2626', status: 'raw' },
    { label: 'MVC worker 400', run: 'RUN-169', p95: mvc400a.latencyMs.p95, p99: mvc400a.latencyMs.p99, color: '#d97706', status: 'raw 반복 1' },
    { label: 'MVC worker 400', run: 'RUN-170', p95: mvc400b.latencyMs.p95, p99: mvc400b.latencyMs.p99, color: '#d97706', status: 'raw 반복 2' },
  ];
  const left = 90;
  const p95X = 425;
  const p99X = 780;
  const width = 270;
  const max = 10000;
  const y = [205, 305, 405, 505];
  const ticks = [0, 2500, 5000, 7500, 10000];
  const marks = [];
  marks.push(`<text x="${left}" y="60" class="title">최신성 조건과 MVC worker 조정의 한계</text>`);
  marks.push(`<text x="${left}" y="90" class="subtitle">AI 1초 · frame/reconnect 0.5초 · VU 70 / 목표: p95 ≤ 1,500ms, p99 ≤ 1,800ms</text>`);
  marks.push(`<text x="${p95X}" y="140" class="label">p95 (ms)</text>`);
  marks.push(`<text x="${p99X}" y="140" class="label">p99 (ms)</text>`);
  for (const tick of ticks) {
    [p95X, p99X].forEach((base) => {
      const x = base + (tick / max) * width;
      marks.push(`<line x1="${x}" y1="160" x2="${x}" y2="555" class="grid"/>`);
      marks.push(`<text x="${x}" y="585" class="small" text-anchor="middle">${tick.toLocaleString()}</text>`);
    });
  }
  [
    { base: p95X, target: 1500, label: '목표 1,500' },
    { base: p99X, target: 1800, label: '목표 1,800' },
  ].forEach(({ base, target, label }) => {
    const x = base + (target / max) * width;
    marks.push(`<line x1="${x}" y1="155" x2="${x}" y2="560" stroke="#0f766e" stroke-width="2" stroke-dasharray="6 5"/>`);
    marks.push(`<text x="${x + 4}" y="155" class="small" fill="#0f766e">${label}</text>`);
  });
  rows.forEach((row, index) => {
    marks.push(`<text x="${left}" y="${y[index] + 4}" class="label">${escapeXml(row.label)}</text>`);
    marks.push(`<text x="${left}" y="${y[index] + 26}" class="small">${row.run} · ${row.status}</text>`);
    [
      { base: p95X, value: row.p95 },
      { base: p99X, value: row.p99 },
    ].forEach(({ base, value }) => {
      marks.push(`<rect x="${base}" y="${y[index] - 20}" width="${width}" height="36" rx="5" fill="#e2e8f0"/>`);
      marks.push(`<rect x="${base}" y="${y[index] - 20}" width="${Math.min(value, max) / max * width}" height="36" rx="5" fill="${row.color}"/>`);
      marks.push(`<text x="${base + width + 9}" y="${y[index] + 5}" class="value">${value.toLocaleString()}</text>`);
    });
  });
  marks.push(`<line x1="${left}" y1="630" x2="1110" y2="630" class="axis"/>`);
  marks.push(`<text x="${left}" y="660" class="note">주의: RUN-167/169/170은 monitor failure가 있어 strict 프레임워크 비교가 아닌 raw sensitivity 자료다. MVC worker 400은 두 번 모두 오류를 해소했지만 최신성 목표는 넘었다.</text>`);
  return svgShell('AI 1초 0.5초 frame 조건에서 WebFlux와 MVC worker 조정 비교', marks.join('\n  '));
}

writeSvg('figure-01-core-valid-pair.svg', coreComparison());
writeSvg('figure-02-freshness-worker-tradeoff.svg', freshnessAndTuning());

console.log(outputDir);
