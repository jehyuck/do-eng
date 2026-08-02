const fs = require("fs")
const path = require("path")

const resultsRoot = path.resolve(process.argv[2] || "")
const outputDirectory = path.resolve(process.argv[3] || "")
if (!resultsRoot || !outputDirectory) throw new Error("results root and output directory are required")

const runIds = [1, 2, 3].flatMap((number) => [
  `RUN-20260802-EXP113-BASELINE-00${number}`,
  `RUN-20260802-EXP113-REMEDIATION-00${number}`,
])

function json(file) {
  return JSON.parse(fs.readFileSync(file, "utf8").replace(/^\uFEFF/, ""))
}

function jsonl(file) {
  return fs.readFileSync(file, "utf8").split(/\r?\n/).filter(Boolean).map(JSON.parse)
}

function median(values) {
  if (!values.length) return null
  const sorted = [...values].sort((left, right) => left - right)
  const middle = Math.floor(sorted.length / 2)
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
}

function parseBytes(value) {
  const match = String(value || "").match(/^([\d.]+)([KMG]i?B)/i)
  if (!match) return null
  const scale = { KB: 1e3, KIB: 1024, MB: 1e6, MIB: 1024 ** 2, GB: 1e9, GIB: 1024 ** 3 }
  return Number(match[1]) * scale[match[2].toUpperCase()]
}

function poolMaximum(rows, suffix) {
  const values = rows.flatMap((row) => row.metrics || [])
    .filter((metric) => metric.name.endsWith(suffix) && Number.isFinite(Number(metric.value)))
    .map((metric) => Number(metric.value))
  return values.length ? Math.max(...values) : null
}

function runResult(runId) {
  const directory = path.join(resultsRoot, runId)
  const client = json(path.join(directory, "client-results.json")).summary
  const verification = json(path.join(directory, "verification-summary.json"))
  const correlation = json(path.join(directory, "correlation-summary.json"))
  const mechanism = json(path.join(directory, "connection-mechanism-summary.json"))
  const provenance = json(path.join(directory, "experiment-1-13-provenance.json"))
  const pool = jsonl(path.join(directory, "pool-metrics.jsonl"))
  const container = jsonl(path.join(directory, "container-stats.jsonl"))
    .filter((row) => row.service === "flux-corrected")
  const aiStarts = jsonl(path.join(directory, "correlation-join.jsonl"))
    .filter((row) => row.aiStage?.started).length
  const outcome = client.outcomeCounts
  const uncontrolled = client.failedRequests - outcome.HTTP_503_ADMISSION
  const cpu = container.map((row) => Number(String(row.stats.CPUPerc).replace("%", "")))
    .filter(Number.isFinite)
  const memory = container.map((row) => parseBytes(String(row.stats.MemUsage).split("/")[0].trim()))
    .filter(Number.isFinite)
  return {
    runId,
    condition: provenance.condition,
    maxIdleTimeMs: provenance.maxIdleTimeMs,
    validity: verification.measurementValidity,
    aiPrematureClose: correlation.aiPrematureCloseRequests,
    aiStageStarts: aiStarts,
    aiPrematureCloseRate: aiStarts ? correlation.aiPrematureCloseRequests / aiStarts : null,
    connectionPrematureClose: mechanism.prematureConnectionEvents,
    reusedPrematureClose: mechanism.reusedChannelEvents,
    newPrematureClose: mechanism.newChannelEvents,
    mockCloseBeforeAcquire: mechanism.mockCloseBeforeAcquire,
    mockCloseAfterAcquire: mechanism.mockCloseAfterAcquire,
    preparedWithoutSent: mechanism.withRequestPrepared - mechanism.withRequestSent,
    http200: outcome.HTTP_200_ACCEPTED,
    http500: outcome.HTTP_500_UNCONTROLLED,
    controlled503: outcome.HTTP_503_ADMISSION,
    clientTimeout: outcome.CLIENT_TIMEOUT,
    connectionError: outcome.CONNECTION_ERROR,
    uncontrolledFailure: uncontrolled,
    completedRequests: client.completedRequests,
    http500Rate: client.completedRequests ? outcome.HTTP_500_UNCONTROLLED / client.completedRequests : null,
    connectionErrorRate: client.completedRequests ? outcome.CONNECTION_ERROR / client.completedRequests : null,
    acceptedP50Ms: client.latencyByOutcome.HTTP_200_ACCEPTED.p50,
    acceptedP95Ms: client.latencyByOutcome.HTTP_200_ACCEPTED.p95,
    acceptedP99Ms: client.latencyByOutcome.HTTP_200_ACCEPTED.p99,
    throughputRps: client.throughputRequestsPerSecond,
    missionCompletions: verification.missionCompletionCount,
    aiCompleted: verification.mockMetrics.aiCompleted,
    storageCompleted: verification.mockMetrics.storageCompleted,
    drainTimeToZeroMs: verification.systemOutcome.drain.timeToZeroMs,
    clientEventLoopDelayP95Ms: client.loadGenerator.eventLoopDelayMs.p95,
    appCpuMaxPercent: cpu.length ? Math.max(...cpu) : null,
    appCpuMedianPercent: median(cpu),
    appMemoryMaxBytes: memory.length ? Math.max(...memory) : null,
    poolMaxActive: poolMaximum(pool, "active.connections"),
    poolMaxPending: poolMaximum(pool, "pending.connections"),
    connectionChurn: mechanism.connectionChurn,
    outcomeCounts: outcome,
  }
}

const runs = runIds.map(runResult)
const byCondition = Object.fromEntries(["BASELINE", "REMEDIATION"].map((condition) => {
  const selected = runs.filter((run) => run.condition === condition)
  const numericFields = [
    "aiPrematureClose", "aiPrematureCloseRate", "connectionPrematureClose",
    "reusedPrematureClose", "newPrematureClose", "mockCloseBeforeAcquire",
    "mockCloseAfterAcquire", "preparedWithoutSent", "http200", "http500",
    "controlled503", "clientTimeout", "connectionError", "uncontrolledFailure",
    "http500Rate", "connectionErrorRate", "acceptedP50Ms", "acceptedP95Ms",
    "acceptedP99Ms", "throughputRps", "missionCompletions", "aiCompleted",
    "storageCompleted", "drainTimeToZeroMs", "clientEventLoopDelayP95Ms",
    "appCpuMaxPercent", "appCpuMedianPercent", "appMemoryMaxBytes",
    "poolMaxActive", "poolMaxPending",
  ]
  const statistics = {}
  for (const field of numericFields) {
    const values = selected.map((run) => run[field]).filter(Number.isFinite)
    statistics[field] = {
      values,
      sum: values.reduce((total, value) => total + value, 0),
      min: values.length ? Math.min(...values) : null,
      max: values.length ? Math.max(...values) : null,
      median: median(values),
    }
  }
  return [condition, { runs: selected, statistics }]
}))

const baseline = byCondition.BASELINE
const remediation = byCondition.REMEDIATION
const allValid = runs.every((run) => run.validity === "VALID")
const baselineReproducedRuns = baseline.runs.filter((run) => run.mockCloseBeforeAcquire > 0).length
const remediationMechanismZero = remediation.runs.every((run) => run.mockCloseBeforeAcquire === 0)
const baselinePremature = baseline.statistics.aiPrematureClose.sum
const remediationPremature = remediation.statistics.aiPrematureClose.sum
const reduction = baselinePremature > 0 ? 1 - remediationPremature / baselinePremature : null
const outcomeNames = Object.keys(runs[0].outcomeCounts)
const newFailureCategories = outcomeNames.filter((name) =>
  baseline.runs.every((run) => Number(run.outcomeCounts[name] || 0) === 0)
    && remediation.runs.some((run) => Number(run.outcomeCounts[name] || 0) > 0)
    && name !== "HTTP_200_ACCEPTED" && name !== "HTTP_503_ADMISSION")
const uncontrolledGuard = remediation.statistics.uncontrolledFailure.median
  <= baseline.statistics.uncontrolledFailure.median
const successGuard = remediation.statistics.http200.median
  >= baseline.statistics.http200.median * 0.9
const latencyGuard = remediation.statistics.acceptedP95Ms.median
  <= baseline.statistics.acceptedP95Ms.median * 1.1
const mechanismEffective = remediationMechanismZero && reduction !== null && reduction >= 0.9

let verdict
if (!allValid) verdict = "INCONCLUSIVE_INVALID_RUN"
else if (baselineReproducedRuns < 2) verdict = "INCONCLUSIVE_NOT_REPRODUCED"
else if (mechanismEffective && newFailureCategories.length === 0
  && uncontrolledGuard && successGuard && latencyGuard) verdict = "ACCEPTED_REMEDIATION"
else if (mechanismEffective) verdict = "EFFECTIVE_BUT_NOT_ACCEPTED"
else verdict = "NOT_EFFECTIVE"

const pairs = [1, 2, 3].map((number) => {
  const baselineRun = runs.find((run) => run.runId.endsWith(`BASELINE-00${number}`))
  const remediationRun = runs.find((run) => run.runId.endsWith(`REMEDIATION-00${number}`))
  return { pair: number, baseline: baselineRun, remediation: remediationRun }
})
const verdictArtifact = {
  generatedAt: new Date().toISOString(), verdict, allValid, baselineReproducedRuns,
  remediationMechanismZero, aiPrematureCloseReduction: reduction,
  newFailureCategories, guards: { uncontrolledGuard, successGuard, latencyGuard },
  adopted: verdict === "ACCEPTED_REMEDIATION",
}

fs.mkdirSync(outputDirectory, { recursive: true })
fs.writeFileSync(path.join(outputDirectory, "experiment-1-13-paired-summary.json"), `${JSON.stringify(pairs, null, 2)}\n`)
fs.writeFileSync(path.join(outputDirectory, "experiment-1-13-condition-summary.json"), `${JSON.stringify(byCondition, null, 2)}\n`)
fs.writeFileSync(path.join(outputDirectory, "experiment-1-13-verdict.json"), `${JSON.stringify(verdictArtifact, null, 2)}\n`)
process.stdout.write(`${JSON.stringify(verdictArtifact)}\n`)
