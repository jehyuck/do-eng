/*
 * Builds a provenance-first evidence addendum from already recorded DoEng runs.
 * It never executes an experiment and refuses to overwrite an existing package.
 */
const fs = require('fs')
const path = require('path')
const crypto = require('crypto')
const { execFileSync } = require('child_process')

const root = path.resolve(__dirname, '..', '..')
const packageName = 'DoEng-WebFlux-Evidence-Addendum-20260731'
const out = path.join(root, 'evidence-addendum', packageName)
const resultsRoot = path.join(root, 'experiment', 'results')

if (fs.existsSync(out)) {
  throw new Error(`Refusing to overwrite existing evidence package: ${out}`)
}

const runIds = [
  'RUN-20260729-155',
  'RUN-20260729-156',
  'RUN-20260731-166',
  'RUN-20260731-167',
  'RUN-20260731-168',
  'RUN-20260731-169',
  'RUN-20260731-170',
]
const coreRuns = ['RUN-20260729-155', 'RUN-20260729-156', 'RUN-20260731-166']
const copied = []
const missing = []

function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')
}

function ensureParent(file) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
}

function copy(source, destination, group, method = 'FOUND_EXISTING_RAW_ARTIFACT') {
  if (!fs.existsSync(source)) {
    missing.push({ source: path.relative(root, source).replaceAll('\\', '/'), group })
    return false
  }
  ensureParent(destination)
  fs.copyFileSync(source, destination)
  copied.push({
    group,
    method,
    source: path.relative(root, source).replaceAll('\\', '/'),
    destination: path.relative(out, destination).replaceAll('\\', '/'),
    sha256: sha256(source),
    bytes: fs.statSync(source).size,
  })
  return true
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''))
}

function percentile(values, fraction) {
  if (!values.length) return null
  const sorted = [...values].sort((a, b) => a - b)
  return sorted[Math.max(0, Math.ceil(sorted.length * fraction) - 1)]
}

function numericSummary(values) {
  const clean = values.filter((value) => Number.isFinite(value))
  if (!clean.length) return { count: 0, min: null, p95: null, max: null }
  return {
    count: clean.length,
    min: Math.min(...clean),
    p95: percentile(clean, 0.95),
    max: Math.max(...clean),
  }
}

function valuesAt(object, get) {
  return object.map(get).filter((value) => Number.isFinite(value))
}

function parseJsonl(file) {
  if (!fs.existsSync(file)) return []
  return fs.readFileSync(file, 'utf8').trim().split(/\r?\n/).filter(Boolean).map(JSON.parse)
}

function summarizeRun(runId) {
  const dir = path.join(resultsRoot, runId)
  const client = readJson(path.join(dir, 'client-summary.stdout.json'))
  const appSamples = parseJsonl(path.join(dir, 'application-metrics.jsonl'))
  const databaseSamples = parseJsonl(path.join(dir, 'database-metrics.jsonl'))
  const bodies = appSamples
    .map((sample) => sample.application && sample.application.body)
    .filter(Boolean)
  const mocks = appSamples
    .map((sample) => sample.mock && sample.mock.body)
    .filter(Boolean)
  const failures = appSamples.flatMap((sample) => sample.failures || [])
  const countFailures = (name) => failures.filter((failure) => failure.name === name).length
  const get = (object, chain) => chain.reduce((current, key) => current && current[key], object)
  const app = (chain) => numericSummary(valuesAt(bodies, (body) => get(body, chain)))
  const mock = (chain) => numericSummary(valuesAt(mocks, (body) => get(body, chain)))
  return {
    runId,
    client: {
      implementation: client.implementation,
      activeMissions: client.activeMissions,
      intervalMs: client.intervalMs,
      reconnectDelayMs: client.reconnectDelayMs,
      scheduledRequests: client.scheduledRequests,
      completedRequests: client.completedRequests,
      successfulRequests: client.successfulRequests,
      failedRequests: client.failedRequests,
      errorRate: client.errorRate,
      p95Ms: client.latencyMs.p95,
      p99Ms: client.latencyMs.p99,
      targetP95Ms: client.targetP95Ms,
    },
    monitor: {
      applicationSampleCount: appSamples.length,
      applicationFailureCount: failures.length,
      mockMetricsTimeoutCount: countFailures('mock.__metrics'),
      appMetrics: {
        heapUsedBytes: app(['jvm', 'heapUsedBytes']),
        liveThreads: app(['jvm', 'liveThreads']),
        processCpuUsage: app(['jvm', 'processCpuUsage']),
        gcPauseCount: app(['jvm', 'gcPauseCount']),
        gcPauseTotalMs: app(['jvm', 'gcPauseTotalMs']),
        gcPauseMaxMs: app(['jvm', 'gcPauseMaxMs']),
        requestBusy: app(['requestRuntime', 'busy']),
        requestMax: app(['requestRuntime', 'max']),
        requestQueue: app(['requestRuntime', 'queue']),
        eventLoopPendingSum: app(['requestRuntime', 'pendingSum']),
        eventLoopPendingMax: app(['requestRuntime', 'pendingMax']),
        outboundActive: app(['outboundHttp', 'active']),
        outboundPending: app(['outboundHttp', 'pending']),
        outboundMax: app(['outboundHttp', 'max']),
        databaseActive: app(['databasePool', 'active']),
        databasePending: app(['databasePool', 'pending']),
        databaseMax: app(['databasePool', 'max']),
      },
      mockMetrics: {
        aiInFlight: mock(['aiInFlight']),
        storageInFlight: mock(['storageInFlight']),
      },
      database: {
        sampleCount: databaseSamples.length,
        failureCount: databaseSamples.filter((sample) => !sample.ok).length,
        threadsConnected: numericSummary(valuesAt(databaseSamples, (sample) => sample.threadsConnected)),
        threadsRunning: numericSummary(valuesAt(databaseSamples, (sample) => sample.threadsRunning)),
      },
    },
  }
}

function git(args) {
  try {
    return execFileSync('git', ['-c', 'safe.directory=*', '-C', root, ...args], { encoding: 'utf8' })
  } catch (error) {
    return `GIT_COMMAND_FAILED\n${error.stdout || ''}${error.stderr || ''}`
  }
}

function write(relative, content) {
  const destination = path.join(out, relative)
  ensureParent(destination)
  fs.writeFileSync(destination, content, 'utf8')
}

// Plans are copied exactly; this is recovery, not a new experiment plan.
for (const file of [
  '57_ai_two_second_vu120_steady_pair_plan.md',
  '12_image_mission_webflux_mvc_experiment_plan.md',
  '65_realtime_half_second_vu70_cross_reproduction_plan.md',
  '66_mvc_vu70_jfr_diagnostic_plan.md',
  '67_mvc_thread400_sensitivity_plan.md',
  '69_mvc_thread400_reproduction_plan.md',
]) {
  copy(path.join(root, 'docs', file), path.join(out, 'plan', file), 'plan')
}

const clientFiles = ['client-summary.stdout.json', 'client-results.json', 'client-progress.jsonl']
const monitorFiles = [
  'application-metrics.jsonl', 'database-metrics.jsonl', 'container-monitor-summary.json',
  'container-stats.jsonl', 'monitor.stdout.log', 'monitor.stderr.log', 'monitor-process-status.json',
  'timeseries.csv', 'timeseries.svg', 'mock-metrics-after.json', 'mock-requests.json',
]
const recoveredFiles = [
  'environment.json', 'run-config.json', 'mock-control.json', 'verification-summary.json',
  'db-before.json', 'db-after.json', 'storage-before.json', 'storage-after.json',
  'mission-completions.json', 'prepared-users.json',
]
for (const runId of runIds) {
  const dir = path.join(resultsRoot, runId)
  for (const file of clientFiles) copy(path.join(dir, file), path.join(out, 'client', runId, file), 'client')
  for (const file of monitorFiles) copy(path.join(dir, file), path.join(out, 'monitor', runId, file), 'monitor')
  for (const file of recoveredFiles) copy(path.join(dir, file), path.join(out, 'recovered', runId, file), 'recovered')
}
for (const file of [
  'jfr-command.json', 'jfr-recovery-validation.json', 'jfr-summary-recovered.txt',
  'jvm-recording-recovered.jfr', 'jfr-core-events-recovered.json',
  'jfr-io-events-recovered.json', 'jfr-key-events-partial-terminated.json',
]) {
  copy(path.join(resultsRoot, 'RUN-20260731-168', file), path.join(out, 'jfr', 'RUN-20260731-168', file), 'jfr')
}

const run155 = readJson(path.join(resultsRoot, 'RUN-20260729-155', 'run-config.json'))
const run169 = readJson(path.join(resultsRoot, 'RUN-20260731-169', 'run-config.json'))
const expectedConfigs = new Map()
for (const item of [...run155.composeFiles, ...run169.composeFiles]) {
  expectedConfigs.set(path.normalize(item.path), item.sha256)
}
const recoveredConfig = []
for (const [absoluteSource, expectedHash] of expectedConfigs) {
  const actualHash = fs.existsSync(absoluteSource) ? sha256(absoluteSource) : null
  const relative = path.relative(root, absoluteSource)
  const destination = path.join(out, 'provenance', 'config-recovered', relative)
  const match = actualHash === expectedHash
  if (match) copy(absoluteSource, destination, 'provenance-config', 'RECOVERED_FROM_WORKING_TREE_BYTE_IDENTICAL_TO_RECORDED_RUN_CONFIG')
  recoveredConfig.push({
    source: relative.replaceAll('\\', '/'), expectedSha256: expectedHash, actualSha256: actualHash,
    byteIdenticalToRecordedRunConfig: match, copied: match,
  })
}
const environment155 = readJson(path.join(resultsRoot, 'RUN-20260729-155', 'environment.json'))
for (const item of environment155.source.files.filter((file) =>
  /(?:application\.yml|ExperimentSnapshotEndpoint\.java|ExternalHttpClientConfig\.java)$/.test(file.path),
)) {
  const absoluteSource = path.join(root, item.path)
  const actualHash = fs.existsSync(absoluteSource) ? sha256(absoluteSource) : null
  const relative = path.relative(root, absoluteSource)
  const match = actualHash === item.sha256
  if (match) copy(
    absoluteSource,
    path.join(out, 'provenance', 'config-recovered', relative),
    'provenance-config',
    'RECOVERED_FROM_WORKING_TREE_BYTE_IDENTICAL_TO_RECORDED_ENVIRONMENT',
  )
  recoveredConfig.push({
    source: relative.replaceAll('\\', '/'), expectedSha256: item.sha256, actualSha256: actualHash,
    byteIdenticalToRecordedEnvironment: match, copied: match,
  })
}
write('provenance/config-recovery-index.json', `${JSON.stringify(recoveredConfig, null, 2)}\n`)

// Current runner source is useful to explain the field name, but no historical source hash was retained for it.
copy(
  path.join(root, 'experiment', 'load', 'mission-load.js'),
  path.join(out, 'provenance', 'current-reference-not-past-provenance', 'mission-load.js'),
  'provenance-current-reference',
  'CURRENT_REFERENCE_NOT_PAST_PROVENANCE',
)

const workerDiff = [
  '# MVC worker configuration difference',
  '',
  'The 200-worker value is the base `mvc` environment in `docker-compose.experiment.yaml`.',
  'The 400-worker runs append `docker-compose.mvc-threads-400.yaml`; its only override is `DOENG_MVC_MAX_THREADS: "400"`.',
  'Both files were copied only after their SHA-256 matched the checksums recorded in the original run-config files.',
  '',
  '```diff',
  '- DOENG_MVC_MAX_THREADS: "200"   # base MVC service',
  '+ DOENG_MVC_MAX_THREADS: "400"   # experiment-only override for RUN-20260731-169/170',
  '```',
  '',
].join('\n')
write('provenance/worker200-to400-config-diff.md', workerDiff)

write('provenance/git-recovery-audit.md', [
  '# Git recovery audit', '',
  'Recovery method: read-only Git commands with process-local `safe.directory=*`; no Git configuration, commit, checkout, or remote state was changed.', '',
  '## HEAD', '```text', git(['rev-parse', 'HEAD']).trim(), '```', '',
  '## Recent history', '```text', git(['log', '--oneline', '-8']).trim(), '```', '',
  '## Working-tree status at recovery', '```text', git(['status', '--short']).trim(), '```', '',
  '## Finding', '',
  'The experimental documents, runner, compose overlays, and results are untracked in this repository state. Therefore Git cannot supply a committed historical copy of those files. Where `run-config.json` recorded a SHA-256 and the current working-tree file matches it byte-for-byte, this package labels the copy `RECOVERED_FROM_WORKING_TREE_BYTE_IDENTICAL_TO_RECORDED_RUN_CONFIG`; it does not label it as a Git recovery.', '',
].join('\n'))

const summaries = Object.fromEntries(runIds.map((runId) => [runId, summarizeRun(runId)]))
write('provenance/derived-server-metric-summary.json', `${JSON.stringify({
  generatedFrom: 'existing application-metrics.jsonl and database-metrics.jsonl; derived after the runs, not run-time metadata',
  runs: summaries,
}, null, 2)}\n`)

function fmtPercent(value) { return value == null ? 'n/a' : `${(value * 100).toFixed(2)}%` }
function fmt(value) { return value == null ? 'n/a' : String(value) }
const w155 = summaries['RUN-20260729-155']
const m156 = summaries['RUN-20260729-156']
const f166 = summaries['RUN-20260731-166']
const m167 = summaries['RUN-20260731-167']
const m169 = summaries['RUN-20260731-169']
const m170 = summaries['RUN-20260731-170']
const report = [
  '# DOE-01 - DoEng WebFlux Evidence Addendum', '',
  '> **Scope separation:** this is a July 2026 follow-up validation package for the DoEng project. It is not evidence that the 2023 production project had these settings, load, or performance. No existing 2023 portfolio text was edited.', '',
  '## Purpose and status', '',
  'This package answers an evidence-review request by preserving client results together with server, database, mock, configuration, and gate artifacts. It performs recovery and packaging only; **no new controlled run was executed for this addendum**.', '',
  '## FOUND EXISTING', '',
  `- Valid core pair: RUN-20260729-155 (WebFlux) and RUN-20260729-156 (MVC 200 workers). Both preserve the same 120 active missions, 1 s interval/reconnect delay, 105 s duration, fixture checksum, five base compose checksums, client raw, app/DB/mock/container monitoring, and ` + '`verification-summary.json`' + ' with `valid: true`.',
  `- Valid freshness run: RUN-20260731-166 (WebFlux, 70 active missions, 0.5 s interval/reconnect delay) includes the same raw classes and a successful verification gate.`,
  '- RUN-20260731-167, RUN-20260731-169, and RUN-20260731-170 preserve client and monitoring raw, but lack a completed verification summary and post-run DB/storage evidence. They are retained as raw/diagnostic material only.',
  '- RUN-20260731-168 preserves its client raw, monitoring raw, JFR start command, recovered recording, summary, exports, and recovery validation. Its monitor failures mean it is diagnostic only, not a performance-comparison result.', '',
  '## RECOVERED FROM GIT / provenance', '',
  '- `provenance/git-recovery-audit.md` records the read-only Git audit: HEAD is `8e856468b36dcb1d7297afc05461af01d6dd6424` and the experimental assets are untracked in this repository state.',
  '- Because Git has no committed historical experimental copy, no experimental file is presented as “recovered from Git.”',
  '- The compose files required by RUN-155/156 and the 400-worker overlay required by RUN-169/170 were recovered from the current working tree **only after** their SHA-256 matched hashes inside original `run-config.json`. See `provenance/config-recovery-index.json`.', '',
  '## NEW CONTROLLED RUNS', '',
  'None. Re-running would create new 2026 measurements; it cannot repair the provenance of the recorded runs. The valid 155/156 pair is sufficient for the limited core claim below. A new planned, alternating multi-repetition run is required only if the 400-worker sensitivity claim is to be promoted from diagnostic context to accepted evidence.', '',
  '## Core client result and gate state', '',
  '| Run | Implementation | Condition | Success / completed | Error rate | p95 / p99 | Gate |',
  '|---|---|---|---:|---:|---:|---|',
  `| 155 | WebFlux | AI 2 s, VU 120, 1 s | ${w155.client.successfulRequests}/${w155.client.completedRequests} | ${fmtPercent(w155.client.errorRate)} | ${w155.client.p95Ms}/${w155.client.p99Ms} ms | valid |`,
  `| 156 | MVC (200) | AI 2 s, VU 120, 1 s | ${m156.client.successfulRequests}/${m156.client.completedRequests} | ${fmtPercent(m156.client.errorRate)} | ${m156.client.p95Ms}/${m156.client.p99Ms} ms | valid |`,
  `| 166 | WebFlux | AI 1 s, VU 70, 0.5 s | ${f166.client.successfulRequests}/${f166.client.completedRequests} | ${fmtPercent(f166.client.errorRate)} | ${f166.client.p95Ms}/${f166.client.p99Ms} ms | valid |`,
  `| 167 | MVC (200) | AI 1 s, VU 70, 0.5 s | ${m167.client.successfulRequests}/${m167.client.completedRequests} | ${fmtPercent(m167.client.errorRate)} | ${m167.client.p95Ms}/${m167.client.p99Ms} ms | raw only: monitor/gate incomplete |`,
  `| 169 | MVC (400) | AI 1 s, VU 70, 0.5 s | ${m169.client.successfulRequests}/${m169.client.completedRequests} | ${fmtPercent(m169.client.errorRate)} | ${m169.client.p95Ms}/${m169.client.p99Ms} ms | raw only: post-run gate missing |`,
  `| 170 | MVC (400) | AI 1 s, VU 70, 0.5 s | ${m170.client.successfulRequests}/${m170.client.completedRequests} | ${fmtPercent(m170.client.errorRate)} | ${m170.client.p95Ms}/${m170.client.p99Ms} ms | raw only: post-run gate missing |`, '',
  '## Server bottleneck raw: what the recorded snapshots support', '',
  `- RUN-156 MVC: Tomcat busy reached ${m156.monitor.appMetrics.requestBusy.max}/${m156.monitor.appMetrics.requestMax.max}; request queue reached ${m156.monitor.appMetrics.requestQueue.max}; outbound HTTP active reached ${m156.monitor.appMetrics.outboundActive.max}/${m156.monitor.appMetrics.outboundMax.max}; DB pool active reached ${m156.monitor.appMetrics.databaseActive.max}/${m156.monitor.appMetrics.databaseMax.max}. Raw source: ` + '`monitor/RUN-20260729-156/application-metrics.jsonl`' + '.',
  `- RUN-155 WebFlux: Reactor event-loop pending sum/max stayed at ${w155.monitor.appMetrics.eventLoopPendingSum.max}/${w155.monitor.appMetrics.eventLoopPendingMax.max}; outbound HTTP active reached ${w155.monitor.appMetrics.outboundActive.max}/${w155.monitor.appMetrics.outboundMax.max}; DB pool active reached ${w155.monitor.appMetrics.databaseActive.max}/${w155.monitor.appMetrics.databaseMax.max}. Raw source: ` + '`monitor/RUN-20260729-155/application-metrics.jsonl`' + '.',
  `- RUN-166 WebFlux freshness condition: event-loop pending sum/max stayed at ${f166.monitor.appMetrics.eventLoopPendingSum.max}/${f166.monitor.appMetrics.eventLoopPendingMax.max}; outbound active reached ${f166.monitor.appMetrics.outboundActive.max}/${f166.monitor.appMetrics.outboundMax.max}.`,
  '- These observations are correlated with the outcome; they support worker-pool saturation as a strong explanation for RUN-156, but do not by themselves prove a universal framework-level cause.', '',
  '## SLO-field conflict: resolution', '',
  '- Every `client-summary.stdout.json` and `run-config.json` retains `targetP95Ms: 6000`. This is a runner-recorded field, not the integrity gate: the original `verification-summary.json` assertion list contains identity, storage, reconnect, and observability checks, but no p95 acceptance assertion. RUN-156 is `valid: true` despite p95 9,514 ms, which independently confirms that 6,000 ms was not the pass/fail quality gate.',
  '- The follow-up service-quality criterion is documented in `docs/12_image_mission_webflux_mvc_experiment_plan.md` (2026-07-28 revision): for AI delay D, p95 <= D+500 ms and p99 <= D+800 ms. This package retains the applied plans and raw latency summaries; it does not rewrite prior results.',
  `- Under that criterion, RUN-155 with D=2,000 ms meets p95 ${w155.client.p95Ms} <= 2,500 and p99 ${w155.client.p99Ms} <= 2,800. RUN-166 with D=1,000 ms meets p95 ${f166.client.p95Ms} <= 1,500 and p99 ${f166.client.p99Ms} <= 1,800.`,
  '- `provenance/current-reference-not-past-provenance/mission-load.js` is included only to explain the current runner field. It is explicitly not used as historical source provenance.', '',
  '## Worker configuration difference', '',
  '- Base MVC compose sets `DOENG_MVC_MAX_THREADS: "200"`.',
  '- The byte-identified experiment-only overlay for RUN-169/170 changes only that value to `"400"`. See `provenance/worker200-to400-config-diff.md` and the copied config files.',
  '- The two 400-worker raw runs should not be used to claim a validated optimum or to replace the valid 200-worker comparison; their required end gate is missing.', '',
  '## JFR', '',
  '- `jfr/RUN-20260731-168/jvm-recording-recovered.jfr` is the recovered binary recording. `jfr-command.json` records `jcmd ... JFR.start ... settings=profile duration=110s ... maxsize=64m`.',
  '- `jfr-recovery-validation.json` records equal source/copied sizes (28,116,810 bytes) and explains that the automatic copy was bypassed after monitor failures; core and I/O exports were then made after load end. The partial export is explicitly marked unusable.',
  '- Therefore JFR may be reviewed for JVM/IO diagnostic hypotheses, but it is not accepted performance evidence for the core pair.', '',
  '## STILL MISSING / claims to re-review', '',
  '- No historical committed copy of experimental configs or runner is available in Git; checksum-matched working-tree recovery is the strongest available configuration provenance.',
  '- No accepted end-to-end gate exists for RUN-167/169/170; do not cite them as valid comparative measurements.',
  '- No valid-pair JFR run exists; RUN-168 is diagnostic-only.',
  '- The package uses HTTP mock AI/storage and local MariaDB. It provides no evidence for real AI model behavior, real S3 latency, multi-host networking, or 2023 production capacity.',
  '- The defensible portfolio claim is narrow: in this controlled 2026 Base64 image -> external AI/storage mock -> DB pipeline, the valid 155/156 pair shows WebFlux retained the recorded freshness target while MVC with 200 request workers saturated and failed many requests. It is not a universal "WebFlux is faster" claim.', '',
  '## Package map', '',
  '- `plan/`: exact existing plans.',
  '- `client/`: client summaries, request results, and progress raw.',
  '- `monitor/`: application, DB, mock, container, and time-series sources.',
  '- `recovered/`: original environment/run config, controls, verification, DB/storage, and completion artifacts.',
  '- `jfr/`: recovered JFR artifacts for RUN-168.',
  '- `provenance/`: artifact manifest, Git audit, checksum recovery index, config diff, and post-run derived metric summary.', '',
].join('\n')
write('EVIDENCE_REVIEW_RESPONSE.md', `${report}\n`)

const manifestHeader = [
  '# DoEng WebFlux Evidence Addendum Manifest', '',
  `Package: ${packageName}`,
  'Purpose: provenance-preserving July 2026 follow-up evidence package; not a rewrite of 2023 portfolio evidence.',
  'Build behavior: recovered existing files only; no load test, container start, database mutation, Git mutation, or overwrite was performed.',
  '',
  '## Artifact inventory', '',
  '| Group | Method | Source | Packaged path | SHA-256 | Bytes |',
  '|---|---|---|---|---|---:|',
  ...copied.map((item) => `| ${item.group} | ${item.method} | ${item.source} | ${item.destination} | ${item.sha256} | ${item.bytes} |`),
  '',
  '## Missing source artifacts (preserved as missing; not synthesized)', '',
  ...(missing.length ? missing.map((item) => `- ${item.group}: ${item.source}`) : ['- None']),
  '',
  '## Generated-after-run files', '',
  '- `EVIDENCE_REVIEW_RESPONSE.md`, `provenance/artifact-index.json`, `provenance/config-recovery-index.json`, `provenance/git-recovery-audit.md`, `provenance/worker200-to400-config-diff.md`, and `provenance/derived-server-metric-summary.json` are recovery/package materials produced after the recorded runs. They are not presented as run-time metadata.',
  '',
].join('\n')
write('MANIFEST.md', `${manifestHeader}\n`)
write('provenance/artifact-index.json', `${JSON.stringify({
  generatedAfterRun: true,
  purpose: 'Inventory of copied original artifacts and their package hashes',
  artifacts: copied,
  missing,
}, null, 2)}\n`)

console.log(JSON.stringify({ package: out, copied: copied.length, missing: missing.length, coreRuns }, null, 2))
