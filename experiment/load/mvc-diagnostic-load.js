const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const mode = (process.env.MODE || 'INGRESS').toUpperCase();
const payloadProfile = (process.env.PAYLOAD_PROFILE || 'REAL').toUpperCase();
const activeUsers = Number(process.env.ACTIVE_USERS || 160);
const intervalMs = Number(process.env.INTERVAL_MS || 1000);
const durationMs = Number(process.env.DURATION_MS || 60000);
const requestTimeoutMs = Number(process.env.REQUEST_TIMEOUT_MS || 10000);
const runId = process.env.EXPERIMENT_RUN_ID || `MVC-DIAG-${Date.now()}`;
const targetUrl = process.env.TARGET_URL || 'http://127.0.0.1:8002/experiment/mvc-probe';
const answer = process.env.ANSWER || 'happy';
const sceneId = process.env.SCENE_ID || '2';
const resultPath = process.env.RESULT_PATH || path.join(process.cwd(), 'mvc-diagnostic-results.json');
const progressPath = process.env.PROGRESS_PATH || path.join(process.cwd(), 'mvc-diagnostic-progress.jsonl');
const fixturePath = process.env.FIXTURE_PATH || path.join(process.cwd(), 'image', 'arc.jpg');

function loadTokens() {
  if (!process.env.AUTH_TOKENS_PATH) return null;
  const value = JSON.parse(fs.readFileSync(process.env.AUTH_TOKENS_PATH, 'utf8').replace(/^\uFEFF/, ''));
  if (!Array.isArray(value) || value.length !== activeUsers ||
      value.some((item) => typeof item !== 'string' || item.trim() === '') ||
      new Set(value).size !== value.length) {
    throw new Error('AUTH_TOKENS_PATH must contain ACTIVE_USERS distinct non-empty strings');
  }
  return value;
}

const perVuTokens = loadTokens();

function buildPayload() {
  const fixtureBytes = fs.readFileSync(fixturePath);
  if (payloadProfile === 'SMALL') {
    const bytes = fixtureBytes.subarray(0, 1024);
    return `data:image/jpeg;base64,${bytes.toString('base64')}`;
  }
  return `data:image/jpeg;base64,${fixtureBytes.toString('base64')}`;
}

function authFor(user) {
  if (perVuTokens) return perVuTokens[user - 1];
  if (process.env.AUTH_TOKEN) return process.env.AUTH_TOKEN;
  return null;
}

function quantile(values, q) {
  if (!values.length) return null;
  const sorted = values.slice().sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor((sorted.length - 1) * q))];
}

const image = buildPayload();
const fixtureBytes = fs.readFileSync(fixturePath);
const payloadBytes = payloadProfile === 'SMALL' ? fixtureBytes.subarray(0, 1024) : fixtureBytes;
const requestJsonBytes = Buffer.byteLength(JSON.stringify({ image }));
fs.writeFileSync(progressPath, '');
const requests = [];
const timers = [];
let inFlight = 0;
let maxInFlight = 0;
let stopped = false;
const startedAt = Date.now();

function writeProgress() {
  const now = Date.now();
  const completed = requests.filter((item) => item.completedAt !== null).length;
  const http200 = requests.filter((item) => item.status === 200).length;
  const timeouts = requests.filter((item) => item.outcome === 'timeout').length;
  fs.appendFileSync(progressPath, `${JSON.stringify({
    capturedAt: new Date(now).toISOString(),
    elapsedMs: now - startedAt,
    started: requests.length,
    completed,
    inFlight,
    http200,
    timeout: timeouts
  })}\n`);
}

async function submit(user, sequence) {
  if (stopped) return;
  const record = {
    requestId: `${runId}-u${user}-r${sequence}`,
    user,
    sequence,
    startedAt: new Date().toISOString(),
    completedAt: null,
    status: null,
    outcome: null,
    latencyMs: null,
    error: null
  };
  requests.push(record);
  inFlight += 1;
  maxInFlight = Math.max(maxInFlight, inFlight);
  const start = Date.now();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), requestTimeoutMs);
  try {
    const headers = {
      'Content-Type': 'application/json',
      'X-Experiment-Run-Id': runId,
      'X-Experiment-Request-Id': record.requestId
    };
    const auth = authFor(user);
    if (auth && (mode === 'TOKEN_AI_STORAGE' || mode === 'FULL')) {
      headers.Authorization = auth;
    }
    if (mode === 'FULL') headers['X-Mission-Run-Id'] = `${runId}-u${user}`;
    const query = mode === 'FULL'
      ? `answer=${encodeURIComponent(answer)}&sceneId=${encodeURIComponent(sceneId)}`
      : `mode=${encodeURIComponent(mode)}&answer=${encodeURIComponent(answer)}&runId=${encodeURIComponent(runId)}`;
    const response = await fetch(`${targetUrl}${targetUrl.includes('?') ? '&' : '?'}${query}`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ image }),
      signal: controller.signal
    });
    record.status = response.status;
    record.body = (await response.text()).slice(0, 256);
    record.outcome = response.status >= 200 && response.status < 300 ? 'success' : 'http';
  } catch (error) {
    record.outcome = error.name === 'AbortError' ? 'timeout' : 'connectionError';
    record.error = String(error.message || error);
  } finally {
    clearTimeout(timeout);
    record.completedAt = new Date().toISOString();
    record.latencyMs = Date.now() - start;
    inFlight -= 1;
  }
}

for (let user = 1; user <= activeUsers; user += 1) {
  let sequence = 0;
  const tick = () => {
    if (stopped) return;
    sequence += 1;
    void submit(user, sequence);
  };
  tick();
  timers.push(setInterval(tick, intervalMs));
}
const progressTimer = setInterval(writeProgress, 1000);
setTimeout(async () => {
  stopped = true;
  timers.forEach(clearInterval);
  clearInterval(progressTimer);
  writeProgress();
  while (inFlight > 0) await new Promise((resolve) => setTimeout(resolve, 50));
  const latencies = requests.map((item) => item.latencyMs).filter((value) => Number.isFinite(value));
  const elapsedSeconds = durationMs / 1000;
  const result = {
    runId,
    mode,
    payloadProfile,
    targetUrl,
    activeUsers,
    intervalMs,
    durationMs,
    requestTimeoutMs,
    started: requests.length,
    completed: requests.filter((item) => item.completedAt !== null).length,
    http200: requests.filter((item) => item.status === 200).length,
    http4xx: requests.filter((item) => item.status >= 400 && item.status < 500).length,
    http5xx: requests.filter((item) => item.status >= 500).length,
    timeout: requests.filter((item) => item.outcome === 'timeout').length,
    connectionError: requests.filter((item) => item.outcome === 'connectionError').length,
    p50: quantile(latencies, 0.50),
    p95: quantile(latencies, 0.95),
    p99: quantile(latencies, 0.99),
    max: latencies.length ? Math.max(...latencies) : null,
    maxInFlight,
    successfulRps: requests.filter((item) => item.status === 200).length / elapsedSeconds,
    totalRps: requests.length / elapsedSeconds,
    payload: {
      sourceFixture: fixturePath,
      binaryBytes: payloadBytes.length,
      binarySha256: crypto.createHash('sha256').update(payloadBytes).digest('hex'),
      base64Chars: image.split(',')[1].length,
      requestJsonBytes,
      profile: payloadProfile
    },
    requests
  };
  fs.writeFileSync(resultPath, JSON.stringify(result, null, 2));
}, durationMs);
