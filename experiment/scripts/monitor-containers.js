const fs = require("fs")
const path = require("path")
const { spawn } = require("child_process")

const runId = requiredEnvironment("MONITOR_RUN_ID")
const outputDirectory = path.resolve(
  requiredEnvironment("MONITOR_OUTPUT_DIRECTORY"),
)
const serverContainerId = requiredEnvironment("MONITOR_SERVER_CONTAINER_ID")
const databaseContainerId = requiredEnvironment(
  "MONITOR_DATABASE_CONTAINER_ID",
)
const durationMs = positiveInteger("MONITOR_DURATION_MS")
const intervalMs = positiveInteger("MONITOR_INTERVAL_MS")
const databaseIntervalMs = positiveInteger("MONITOR_DATABASE_INTERVAL_MS")
const containerMap = JSON.parse(requiredEnvironment("MONITOR_CONTAINER_MAP"))
const applicationMetricsUrl = requiredEnvironment("MONITOR_APP_METRICS_URL")
const mockMetricsUrl = requiredEnvironment("MONITOR_MOCK_METRICS_URL")
const skipApplicationSnapshot = process.env.MONITOR_SKIP_APPLICATION_SNAPSHOT === "1"
const skipMockMetrics = process.env.MONITOR_SKIP_MOCK_METRICS === "1"

const statsPath = path.join(outputDirectory, "container-stats.jsonl")
const applicationPath = path.join(outputDirectory, "application-metrics.jsonl")
const databasePath = path.join(outputDirectory, "database-metrics.jsonl")
const summaryPath = path.join(outputDirectory, "container-monitor-summary.json")

for (const outputPath of [
  statsPath,
  applicationPath,
  databasePath,
  summaryPath,
]) {
  if (fs.existsSync(outputPath)) {
    throw new Error(`monitor output already exists: ${outputPath}`)
  }
}

const serviceByIdPrefix = new Map(
  containerMap.map((container) => [
    String(container.id).slice(0, 12),
    container.service,
  ]),
)
const containerIds = containerMap.map((container) => container.id)
const serverService = containerMap.find(
  (container) => container.id === serverContainerId,
)?.service
const statsStream = fs.createWriteStream(statsPath, { encoding: "utf8" })
const applicationStream = fs.createWriteStream(applicationPath, {
  encoding: "utf8",
})
const databaseStream = fs.createWriteStream(databasePath, {
  encoding: "utf8",
})

const startedAt = new Date()
let statsSamples = 0
let applicationSamples = 0
let applicationFailures = 0
let databaseSamples = 0
let databaseFailures = 0
let skippedApplicationSamples = 0
let skippedDatabaseSamples = 0
let databaseSampleInFlight = false
let stdoutBuffer = ""
let finished = false
let applicationSamplePromise = Promise.resolve()
let applicationSampleInFlight = false

function requiredEnvironment(name) {
  const value = process.env[name]
  if (!value) throw new Error(`${name} is required`)
  return value
}

function positiveInteger(name) {
  const value = Number(requiredEnvironment(name))
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`${name} must be a positive integer`)
  }
  return value
}

function appendStatsLine(line) {
  const cleanedLine = line
    .replace(/\u001b\[[0-9;?]*[ -/]*[@-~]/g, "")
    .trim()
  if (!cleanedLine) return
  const stats = JSON.parse(cleanedLine)
  const containerPrefix = String(stats.Container || "").slice(0, 12)
  statsStream.write(
    `${JSON.stringify({
      runId,
      capturedAt: new Date().toISOString(),
      service: serviceByIdPrefix.get(containerPrefix) || null,
      stats,
    })}\n`,
  )
  statsSamples += 1
}

async function fetchJson(url) {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 750)
  try {
    const response = await fetch(url, { signal: controller.signal })
    const body = await response.text()
    return {
      ok: response.ok,
      status: response.status,
      body: body ? JSON.parse(body) : null,
    }
  } catch (error) {
    return {
      ok: false,
      status: null,
      error: error.name === "AbortError" ? "timeout" : String(error.message),
    }
  } finally {
    clearTimeout(timeout)
  }
}

async function sampleApplicationMetrics() {
  const [application, mock] = await Promise.all([
    skipApplicationSnapshot
      ? Promise.resolve({ ok: true, skipped: true })
      : fetchJson(applicationMetricsUrl),
    skipMockMetrics
      ? Promise.resolve({ ok: true, skipped: true })
      : fetchJson(mockMetricsUrl),
  ])
  const failures = []
  if (!skipApplicationSnapshot && !application.ok) {
    failures.push({
      name: "application.snapshot",
      status: application.status,
      error: application.error || null,
    })
  }
  if (!skipMockMetrics && !mock.ok) {
    failures.push({
      name: "mock.__metrics",
      status: mock.status,
      error: mock.error || null,
    })
  }

  applicationStream.write(
    `${JSON.stringify({
      runId,
      capturedAt: new Date().toISOString(),
      service: serverService,
      application,
      mock,
      failures,
    })}\n`,
  )
  applicationSamples += 1
  applicationFailures += failures.length
}

function scheduleApplicationSample() {
  if (finished) return
  if (applicationSampleInFlight) {
    skippedApplicationSamples += 1
    return
  }
  applicationSampleInFlight = true
  applicationSamplePromise = sampleApplicationMetrics()
    .catch((error) => {
      applicationFailures += 1
      applicationStream.write(
        `${JSON.stringify({
          runId,
          capturedAt: new Date().toISOString(),
          service: serverService,
          application: null,
          mock: null,
          failures: [{
            name: "monitor",
            status: null,
            error: String(error.message),
          }],
        })}\n`,
      )
    })
    .finally(() => {
      applicationSampleInFlight = false
    })
}

function sampleDatabaseMetrics() {
  if (finished) return
  if (databaseSampleInFlight) {
    skippedDatabaseSamples += 1
    return
  }
  databaseSampleInFlight = true
  const sql = [
    "SHOW GLOBAL STATUS",
    "WHERE Variable_name IN ('Threads_connected','Threads_running')",
  ].join(" ")
  const command = "docker"
  const commandArguments = [
      "exec",
      databaseContainerId,
      "mariadb",
      "-N",
      "-B",
      "-udoeng",
      "-pdoeng-experiment-pass",
      "-e",
      sql,
    ]
  const startedAt = new Date()
  const child = spawn(command, commandArguments, { stdio: ["ignore", "pipe", "pipe"] })
  let stdout = ""
  let stderr = ""
  let settled = false
  const timeoutMs = 5000
  const timeout = setTimeout(() => {
    if (settled) return
    settled = true
    child.kill("SIGKILL")
    writeDatabaseSample({
      startedAt,
      finishedAt: new Date(),
      command,
      commandArguments,
      ok: false,
      timeout: true,
      exitCode: null,
      values: {},
      error: `command timeout after ${timeoutMs}ms`,
    })
  }, timeoutMs)
  child.stdout.setEncoding("utf8")
  child.stderr.setEncoding("utf8")
  child.stdout.on("data", (chunk) => { stdout += chunk })
  child.stderr.on("data", (chunk) => { stderr += chunk })
  child.on("error", (error) => {
    if (settled) return
    settled = true
    clearTimeout(timeout)
    writeDatabaseSample({
      startedAt,
      finishedAt: new Date(),
      command,
      commandArguments,
      ok: false,
      timeout: false,
      exitCode: null,
      values: {},
      error: error.message,
    })
  })
  child.on("close", (exitCode) => {
    if (settled) return
    settled = true
    clearTimeout(timeout)
    const values = {}
    if (exitCode === 0) {
      for (const line of stdout.trim().split(/\r?\n/)) {
        const [name, value] = line.split(/\t/)
        if (name && /^\d+$/.test(value || "")) {
          values[name] = Number(value)
        }
      }
    }
    writeDatabaseSample({
      startedAt,
      finishedAt: new Date(),
      command,
      commandArguments,
      ok:
        exitCode === 0 &&
        Number.isFinite(values.Threads_connected) &&
        Number.isFinite(values.Threads_running),
      timeout: false,
      exitCode,
      values,
      error: exitCode === 0 ? null : stderr.trim() || `exit ${exitCode}`,
    })
  })
}

function writeDatabaseSample(sample) {
  const durationMs = sample.finishedAt.getTime() - sample.startedAt.getTime()
  const ok = sample.ok
  if (!ok) databaseFailures += 1
  databaseStream.write(
    `${JSON.stringify({
      runId,
      scheduledAt: sample.scheduledAt || null,
      startedAt: sample.startedAt.toISOString(),
      finishedAt: sample.finishedAt.toISOString(),
      durationMs,
      ok,
      timeout: sample.timeout,
      exitCode: sample.exitCode,
      threadsConnected: sample.values.Threads_connected ?? null,
      threadsRunning: sample.values.Threads_running ?? null,
      command: sample.command,
      commandArguments: sample.commandArguments,
      error: sample.error,
    })}\n`,
  )
  databaseSamples += 1
  databaseSampleInFlight = false
}

const stats = spawn(
  "docker",
  ["stats", "--format", "{{json .}}", ...containerIds],
  { stdio: ["ignore", "pipe", "pipe"] },
)
let statsStderr = ""

stats.stdout.setEncoding("utf8")
stats.stdout.on("data", (chunk) => {
  stdoutBuffer += chunk
  const lines = stdoutBuffer.split(/\r?\n/)
  stdoutBuffer = lines.pop() || ""
  for (const line of lines) appendStatsLine(line)
})
stats.stderr.setEncoding("utf8")
stats.stderr.on("data", (chunk) => {
  statsStderr += chunk
})

scheduleApplicationSample()
sampleDatabaseMetrics()
const applicationTimer = setInterval(scheduleApplicationSample, intervalMs)
const databaseTimer = setInterval(sampleDatabaseMetrics, databaseIntervalMs)

async function finish() {
  if (finished) return
  finished = true
  clearInterval(applicationTimer)
  clearInterval(databaseTimer)
  if (stdoutBuffer.trim()) appendStatsLine(stdoutBuffer)

  stats.kill()
  await new Promise((resolve) => {
    if (stats.exitCode !== null) {
      resolve()
      return
    }
    stats.once("close", resolve)
    setTimeout(resolve, 2000)
  })

      await applicationSamplePromise
      while (databaseSampleInFlight) {
        await new Promise((resolve) => setTimeout(resolve, 25))
      }
  await Promise.all([
    new Promise((resolve) => statsStream.end(resolve)),
    new Promise((resolve) => applicationStream.end(resolve)),
    new Promise((resolve) => databaseStream.end(resolve)),
  ])

  const summary = {
    runId,
    startedAt: startedAt.toISOString(),
    finishedAt: new Date().toISOString(),
    requestedDurationMs: durationMs,
    requestedIntervalMs: intervalMs,
    requestedDatabaseIntervalMs: databaseIntervalMs,
    applicationSnapshotEnabled: !skipApplicationSnapshot,
    mockMetricsPollingEnabled: !skipMockMetrics,
    containers: containerMap,
    statsLines: statsSamples,
    approximateStatsCycles: statsSamples / containerMap.length,
    applicationSamples,
    applicationFailures,
    skippedApplicationSamples,
    skippedDatabaseSamples,
    databaseSamples,
    databaseFailures,
    applicationPath,
    databasePath,
    statsPath,
    statsStderr: statsStderr.trim() || null,
  }
  fs.writeFileSync(summaryPath, `${JSON.stringify(summary, null, 2)}\n`)
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`)
}

setTimeout(() => {
  void finish()
}, durationMs)

process.on("SIGINT", () => {
  void finish()
})
process.on("SIGTERM", () => {
  void finish()
})
