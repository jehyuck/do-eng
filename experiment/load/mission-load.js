const fs = require("fs")
const path = require("path")
const crypto = require("crypto")
const { monitorEventLoopDelay } = require("perf_hooks")
const { responseMatchesSuccess } = require("./response-success-matcher")

const targetUrl =
  process.env.TARGET_URL || "http://127.0.0.1:8000/game/face"
const activeMissions = positiveInteger("ACTIVE_MISSIONS", 1)
const loadScenario = process.env.LOAD_SCENARIO || "single-success"
const accountingMode = process.env.ACCOUNTING_MODE || "legacy"
const initialActiveUsers = positiveInteger(
  "INITIAL_ACTIVE_USERS",
  activeMissions,
)
const activationStepUsers = positiveInteger(
  "ACTIVATION_STEP_USERS",
  activeMissions,
)
const activationIntervalMs = positiveInteger(
  "ACTIVATION_INTERVAL_MS",
  3000,
)
const reconnectDelayMs = positiveInteger("RECONNECT_DELAY_MS", 3000)
const intervalMs = positiveInteger("INTERVAL_MS", 3000)
const durationMs = positiveInteger("DURATION_MS", 30000)
const requestTimeoutMs = positiveInteger("REQUEST_TIMEOUT_MS", 10000)
const targetP95Ms = positiveInteger("TARGET_P95_MS", 3000)
const sceneId = positiveInteger("SCENE_ID", 2)
const answer = process.env.ANSWER || "happy"
const successJsonPath = optionalString("SUCCESS_JSON_PATH")
const sendAuthorization = booleanEnvironment("SEND_AUTHORIZATION", true)
const sendMissionRunId = booleanEnvironment("SEND_MISSION_RUN_ID", true)
const sendSceneId = booleanEnvironment("SEND_SCENE_ID", true)
const authorization =
  process.env.AUTH_TOKEN || "Bearer experiment-member-15"
const authTokensPath = process.env.AUTH_TOKENS_PATH
  ? path.resolve(process.env.AUTH_TOKENS_PATH)
  : null
const syntheticFixtureBytes = optionalPositiveInteger("FIXTURE_BYTES")
const fixturePath = syntheticFixtureBytes
  ? null
  : path.resolve(
      process.env.FIXTURE_PATH ||
        "exec/1-3 (배포 메뉴얼)/assets/backend_pipeline.jpg",
    )
const stopUserOnTrue =
  String(process.env.STOP_USER_ON_TRUE || "false").toLowerCase() === "true"
const arrivalMode = process.env.ARRIVAL_MODE || "aligned"
const experimentRunId =
  process.env.EXPERIMENT_RUN_ID ||
  `mission-${new Date().toISOString().replace(/[:.]/g, "-")}`
const implementation = process.env.IMPLEMENTATION || "unspecified"
const resultPath = process.env.RESULT_PATH
  ? path.resolve(process.env.RESULT_PATH)
  : null
const progressPath = process.env.PROGRESS_PATH
  ? path.resolve(process.env.PROGRESS_PATH)
  : null
const mockMetricsUrl = process.env.MOCK_METRICS_URL || "http://127.0.0.1:9100/__metrics"
const drainObservationSeconds = nonNegativeInteger(
  "DRAIN_OBSERVATION_SECONDS",
  0,
)
const loadStopMockMetricsPath = process.env.LOAD_STOP_MOCK_METRICS_PATH
  ? path.resolve(process.env.LOAD_STOP_MOCK_METRICS_PATH)
  : null
const mockDrainPath = process.env.MOCK_DRAIN_PATH
  ? path.resolve(process.env.MOCK_DRAIN_PATH)
  : null
const mockDrainSummaryPath = process.env.MOCK_DRAIN_SUMMARY_PATH
  ? path.resolve(process.env.MOCK_DRAIN_SUMMARY_PATH)
  : null

if (!["aligned", "staggered"].includes(arrivalMode)) {
  throw new Error("ARRIVAL_MODE must be aligned or staggered")
}

if (!["single-success", "reconnect-ramp"].includes(loadScenario)) {
  throw new Error("LOAD_SCENARIO must be single-success or reconnect-ramp")
}

if (!["legacy", "corrected"].includes(accountingMode)) {
  throw new Error("ACCOUNTING_MODE must be legacy or corrected")
}

if (initialActiveUsers > activeMissions) {
  throw new Error("INITIAL_ACTIVE_USERS must not exceed ACTIVE_MISSIONS")
}

function positiveInteger(name, fallback) {
  const value = Number(process.env[name] || fallback)
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`${name} must be a positive integer`)
  }
  return value
}

function optionalPositiveInteger(name) {
  const rawValue = process.env[name]
  if (rawValue === undefined || rawValue.trim() === "") return null

  const value = Number(rawValue)
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`${name} must be a positive integer when provided`)
  }
  return value
}

function nonNegativeInteger(name, fallback) {
  const value = Number(process.env[name] || fallback)
  if (!Number.isInteger(value) || value < 0) {
    throw new Error(`${name} must be a non-negative integer`)
  }
  return value
}

function optionalString(name) {
  const value = process.env[name]
  return value === undefined || value.trim() === "" ? null : value.trim()
}

function booleanEnvironment(name, fallback) {
  const value = process.env[name]
  if (value === undefined || value.trim() === "") return fallback
  return value.trim().toLowerCase() !== "false"
}

function createDeterministicFixture(size) {
  const buffer = Buffer.allocUnsafe(size)
  for (let index = 0; index < size; index += 1) {
    buffer[index] = (index * 31 + 17) & 0xff
  }
  return buffer
}

function percentile(sortedValues, fraction) {
  if (sortedValues.length === 0) return null
  const index = Math.min(
    sortedValues.length - 1,
    Math.ceil(sortedValues.length * fraction) - 1,
  )
  return sortedValues[index]
}

function errorDetails(error, maxDepth = 3) {
  const chain = []
  let current = error
  let depth = 0
  while (current && depth < maxDepth) {
    chain.push({
      name: current.name || null,
      message: current.message || null,
      code: current.code || null,
      errno: current.errno || null,
      syscall: current.syscall || null,
    })
    current = current.cause
    depth += 1
  }
  const root = chain[chain.length - 1] || {}
  return {
    chain,
    socket: {
      localAddress: error?.address || error?.localAddress || null,
      localPort: error?.localPort || null,
      remoteAddress: error?.hostname || error?.remoteAddress || null,
      remotePort: error?.port || error?.remotePort || null,
      bytesWritten: error?.bytesWritten ?? null,
      bytesRead: error?.bytesRead ?? null,
    },
    rootCode: root.code || null,
  }
}

function transportCategory(error, phase, deadlineAborted) {
  const details = errorDetails(error)
  const text = details.chain
    .map((item) => `${item.name || ""} ${item.message || ""} ${item.code || ""}`)
    .join(" ")
    .toLowerCase()
  if (deadlineAborted) return "CLIENT_ABORT_DEADLINE"
  if (text.includes("econnrefused")) return "CONNECT_REFUSED"
  if (text.includes("etimedout") || text.includes("connect timeout")) return "CONNECT_TIMEOUT"
  if (text.includes("econnreset") || text.includes("socket reset")) return "SOCKET_RESET"
  if (text.includes("socket closed") || text.includes("closed")) return "SOCKET_CLOSED"
  if (text.includes("headers timeout")) return "UNDICI_HEADERS_TIMEOUT"
  if (text.includes("body timeout")) return "UNDICI_BODY_TIMEOUT"
  if (text.includes("undici") || text.includes("socket")) return "UNDICI_SOCKET"
  if (phase === "PHASE_FETCH_HEADERS") return "FETCH_BEFORE_HEADERS_OTHER"
  if (phase === "PHASE_RESPONSE_BODY") return "FETCH_AFTER_HEADERS_OTHER"
  return "UNCLASSIFIED_TRANSPORT"
}

function transportError(error, phase, deadlineAborted) {
  return {
    phase,
    category: transportCategory(error, phase, deadlineAborted),
    details: errorDetails(error),
  }
}

if (fixturePath && !fs.existsSync(fixturePath)) {
  throw new Error(`fixture does not exist: ${fixturePath}`)
}

if (authTokensPath && !fs.existsSync(authTokensPath)) {
  throw new Error(`AUTH_TOKENS_PATH does not exist: ${authTokensPath}`)
}

const perVuAuthorizations = authTokensPath
  ? JSON.parse(fs.readFileSync(authTokensPath, "utf8").replace(/^\uFEFF/, ""))
  : null

if (perVuAuthorizations !== null) {
  if (!Array.isArray(perVuAuthorizations)) {
    throw new Error("AUTH_TOKENS_PATH must contain a JSON array")
  }
  if (perVuAuthorizations.length !== activeMissions) {
    throw new Error(
      `AUTH_TOKENS_PATH token count (${perVuAuthorizations.length}) must equal ACTIVE_MISSIONS (${activeMissions})`,
    )
  }
  if (
    perVuAuthorizations.some(
      (value) => typeof value !== "string" || value.trim() === "",
    )
  ) {
    throw new Error("AUTH_TOKENS_PATH contains an invalid token")
  }
  if (new Set(perVuAuthorizations).size !== perVuAuthorizations.length) {
    throw new Error("AUTH_TOKENS_PATH must contain distinct tokens")
  }
}

const fixtureBuffer = syntheticFixtureBytes
  ? createDeterministicFixture(syntheticFixtureBytes)
  : fs.readFileSync(fixturePath)
const fixtureSource = syntheticFixtureBytes
  ? "synthetic-deterministic-bytes"
  : "file"
const fixtureSha256 = crypto
  .createHash("sha256")
  .update(fixtureBuffer)
  .digest("hex")
const imageBase64 = fixtureBuffer.toString("base64")
const payload = JSON.stringify({
  image: `data:image/jpeg;base64,${imageBase64}`,
})
const requestBodyBytes = Buffer.byteLength(payload)
const requestUrl = new URL(targetUrl)
requestUrl.searchParams.set("answer", answer)
if (sendSceneId) requestUrl.searchParams.set("sceneId", String(sceneId))

const users = Array.from({ length: activeMissions }, (_, index) => ({
  index,
  authorization: perVuAuthorizations
    ? perVuAuthorizations[index]
    : authorization,
  sequence: 0,
  active: true,
  missionNumber: 0,
  missionRunId: null,
  activationStage: null,
  activeMission: false,
  startTimer: null,
  timer: null,
  reconnectTimer: null,
}))

const results = []
let inFlight = 0
let maxInFlight = 0
let scheduledRequests = 0
let startedRequests = 0
let schedulingStopped = false
let activatedUsers = 0
let activeMissionUsers = 0
let progressTimer = null
let completedAtLoadStop = 0
let inFlightAtLoadStop = 0
let successTriggeredVuExits = 0
let successTriggeredReconnects = 0
let prematureVuExits = 0

function writeProgress(event) {
  if (!progressPath) return
  fs.mkdirSync(path.dirname(progressPath), { recursive: true })
  fs.appendFileSync(
    progressPath,
    `${JSON.stringify({
      capturedAt: new Date().toISOString(),
      event,
      inFlight,
      scheduledRequests,
      startedRequests,
      completedRequests: results.length,
      activeUsers: users.filter((user) => user.active).length,
    })}\n`,
    "utf8",
  )
}

function startProgressSampling() {
  writeProgress("started")
  if (!progressPath) return

  progressTimer = setInterval(() => {
    writeProgress("sample")
  }, 1000)
}

function finishProgressSampling() {
  if (progressTimer) {
    clearInterval(progressTimer)
    progressTimer = null
  }
  writeProgress("finished")
}

async function submitFrame(user) {
  if (!user.active || schedulingStopped) return

  user.sequence += 1
  const missionNumber = user.missionNumber
  const missionRunId = user.missionRunId
  const activatedUsersAtSchedule = activatedUsers
  const activeMissionUsersAtSchedule = activeMissionUsers
  scheduledRequests += 1
  startedRequests += 1
  const requestId = `${experimentRunId}-u${user.index + 1}-f${user.sequence}`
  const controller = new AbortController()
  let deadlineAborted = false
  const timeout = setTimeout(() => {
    deadlineAborted = true
    controller.abort()
  }, requestTimeoutMs)
  const startedAt = Date.now()
  const requestStartedAt = new Date(startedAt).toISOString()

  inFlight += 1
  maxInFlight = Math.max(maxInFlight, inFlight)

  let response
  let transport = null
  try {
    try {
      const headers = {
        "Content-Type": "application/json",
        "X-Experiment-Run-Id": experimentRunId,
        "X-Experiment-Request-Id": requestId,
      }
      if (sendAuthorization) headers.Authorization = user.authorization
      if (sendMissionRunId) headers["X-Mission-Run-Id"] = missionRunId
      response = await fetch(requestUrl, {
        method: "POST",
        headers,
        body: payload,
        signal: controller.signal,
      })
    } catch (error) {
      transport = transportError(error, "PHASE_FETCH_HEADERS", deadlineAborted)
      throw error
    }
    let body
    try {
      body = await response.text()
    } catch (error) {
      transport = transportError(error, "PHASE_RESPONSE_BODY", deadlineAborted)
      throw error
    }
    const successTriggerMatched = responseMatchesSuccess(body, successJsonPath)

    results.push({
      requestId,
      user: user.index + 1,
      frame: user.sequence,
      missionNumber,
      missionRunId,
      activationStage: user.activationStage,
      activatedUsersAtSchedule,
      activeMissionUsersAtSchedule,
      status: response.status,
      body,
      latencyMs: Date.now() - startedAt,
      requestStartedAt,
      completedAt: new Date().toISOString(),
      error: null,
      transport: null,
      successTriggerMatched,
    })

    if (
      loadScenario === "reconnect-ramp" &&
      successTriggerMatched &&
      user.activeMission &&
      user.missionRunId === missionRunId
    ) {
      successTriggeredReconnects += 1
      user.activeMission = false
      activeMissionUsers -= 1
      clearInterval(user.timer)
      user.reconnectTimer = setTimeout(() => {
        startReconnectMission(user)
      }, reconnectDelayMs)
    } else if (stopUserOnTrue && successTriggerMatched) {
      user.active = false
      successTriggeredVuExits += 1
      clearInterval(user.timer)
    }
  } catch (error) {
    results.push({
      requestId,
      user: user.index + 1,
      frame: user.sequence,
      missionNumber,
      missionRunId,
      activationStage: user.activationStage,
      activatedUsersAtSchedule,
      activeMissionUsersAtSchedule,
      status: null,
      body: null,
      latencyMs: Date.now() - startedAt,
      requestStartedAt,
      completedAt: new Date().toISOString(),
      error: error.name,
      transport: transport || transportError(error, "PHASE_FETCH_HEADERS", deadlineAborted),
      successTriggerMatched: false,
    })
  } finally {
    clearTimeout(timeout)
    inFlight -= 1
  }
}

function startReconnectMission(user) {
  if (schedulingStopped || user.activeMission) return

  user.active = true
  user.activeMission = true
  user.missionNumber += 1
  user.missionRunId = `${experimentRunId}-u${user.index + 1}-m${user.missionNumber}`
  activeMissionUsers += 1
  void submitFrame(user)
  user.timer = setInterval(() => {
    void submitFrame(user)
  }, intervalMs)
}

function stopScheduling() {
  schedulingStopped = true
  for (const user of users) {
    clearTimeout(user.startTimer)
    clearInterval(user.timer)
    clearTimeout(user.reconnectTimer)
  }
}

async function waitForInFlight() {
  const waitDeadline = Date.now() + requestTimeoutMs + 1000
  while (inFlight > 0 && Date.now() < waitDeadline) {
    await new Promise((resolve) => setTimeout(resolve, 50))
  }
}

async function fetchMockMetrics() {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 2000)
  try {
    const response = await fetch(mockMetricsUrl, { signal: controller.signal })
    const body = await response.text()
    return {
      ok: response.ok,
      status: response.status,
      metrics: body ? JSON.parse(body) : null,
      error: null,
    }
  } catch (error) {
    return {
      ok: false,
      status: null,
      metrics: null,
      error: error.name === "AbortError" ? "timeout" : String(error.message),
    }
  } finally {
    clearTimeout(timeout)
  }
}

function isMockIdle(snapshot) {
  return snapshot.ok &&
    snapshot.metrics &&
    snapshot.metrics.aiInFlight === 0 &&
    snapshot.metrics.storageInFlight === 0
}

async function observeMockDrain(loadStoppedAt) {
  const startedAtMs = Date.now()
  const initial = {
    phase: "load-stop",
    capturedAt: new Date().toISOString(),
    elapsedMs: 0,
    ...(await fetchMockMetrics()),
  }
  if (loadStopMockMetricsPath) {
    fs.writeFileSync(
      loadStopMockMetricsPath,
      `${JSON.stringify({ loadStoppedAt, ...initial }, null, 2)}\n`,
    )
  }

  const samples = [initial]
  for (let second = 1; second <= drainObservationSeconds; second += 1) {
    const dueAt = startedAtMs + second * 1000
    const sleepMs = dueAt - Date.now()
    if (sleepMs > 0) {
      await new Promise((resolve) => setTimeout(resolve, sleepMs))
    }
    const sample = {
      phase: "drain",
      sample: second,
      capturedAt: new Date().toISOString(),
      elapsedMs: Date.now() - startedAtMs,
      ...(await fetchMockMetrics()),
    }
    samples.push(sample)
  }

  if (mockDrainPath) {
    fs.writeFileSync(
      mockDrainPath,
      `${samples.map((sample) => JSON.stringify(sample)).join("\n")}\n`,
    )
  }

  const firstIdle = samples.find(isMockIdle)
  const terminal = samples[samples.length - 1]
  const summary = {
    loadStoppedAt,
    configuredSeconds: drainObservationSeconds,
    sampleCount: samples.length,
    initial,
    timeToZeroMs: firstIdle ? firstIdle.elapsedMs : null,
    drainCompleted: Boolean(firstIdle),
    remainingBacklog: terminal.metrics
      ? {
          aiInFlight: terminal.metrics.aiInFlight,
          storageInFlight: terminal.metrics.storageInFlight,
        }
      : null,
    terminal,
  }
  if (mockDrainSummaryPath) {
    fs.writeFileSync(mockDrainSummaryPath, `${JSON.stringify(summary, null, 2)}\n`)
  }
  return summary
}

async function run() {
  const startedAt = new Date().toISOString()
  startProgressSampling()
  const cpuStarted = process.cpuUsage()
  const eventLoopDelay = monitorEventLoopDelay({ resolution: 20 })
  eventLoopDelay.enable()

  if (loadScenario === "reconnect-ramp") {
    const cohorts = new Map()
    for (const user of users) {
      const stage =
        user.index < initialActiveUsers
          ? 0
          : Math.ceil((user.index + 1 - initialActiveUsers) / activationStepUsers)
      user.activationStage = stage
      user.active = false
      if (!cohorts.has(stage)) cohorts.set(stage, [])
      cohorts.get(stage).push(user)
    }
    for (const [stage, cohort] of cohorts) {
      const stageInitialDelayMs = stage * activationIntervalMs
      for (const [cohortIndex, user] of cohort.entries()) {
        const phaseOffsetMs =
          arrivalMode === "staggered"
            ? Math.floor((cohortIndex * activationIntervalMs) / cohort.length)
            : 0
        const initialDelayMs =
          stageInitialDelayMs + phaseOffsetMs
        user.startTimer = setTimeout(() => {
          activatedUsers += 1
          startReconnectMission(user)
        }, initialDelayMs)
      }
    }
  } else {
    for (const user of users) {
      const phaseOffsetMs =
        arrivalMode === "staggered"
          ? Math.floor((user.index * intervalMs) / activeMissions)
          : 0
      const initialDelayMs =
        arrivalMode === "staggered" ? phaseOffsetMs : intervalMs
      user.startTimer = setTimeout(() => {
        user.missionNumber = 1
        user.missionRunId = `${experimentRunId}-u${user.index + 1}-m1`
        void submitFrame(user)
        user.timer = setInterval(() => {
          void submitFrame(user)
        }, intervalMs)
      }, initialDelayMs)
    }
  }

  await new Promise((resolve) => setTimeout(resolve, durationMs))
  stopScheduling()
  const loadStoppedAt = new Date().toISOString()
  completedAtLoadStop = results.length
  inFlightAtLoadStop = inFlight
  const mockDrainPromise = observeMockDrain(loadStoppedAt)
  await waitForInFlight()
  const mockDrain = await mockDrainPromise
  finishProgressSampling()

  const latencies = results
    .filter((result) => result.error === null)
    .map((result) => result.latencyMs)
    .sort((left, right) => left - right)
  const statusCounts = {}

  for (const result of results) {
    const key = result.error || String(result.status)
    statusCounts[key] = (statusCounts[key] || 0) + 1
  }

  const outcomeCategories = {
    HTTP_200_ACCEPTED: [],
    HTTP_503_ADMISSION: [],
    HTTP_503_DOWNSTREAM: [],
    HTTP_4XX_DOWNSTREAM: [],
    HTTP_5XX_DOWNSTREAM: [],
    HTTP_500_UNCONTROLLED: [],
    HTTP_OTHER: [],
    CLIENT_TIMEOUT: [],
    CLIENT_ABORT: [],
    CONNECTION_ERROR: [],
    UNCLASSIFIED: [],
  }
  for (const result of results) {
    let category = "UNCLASSIFIED"
    if (result.error === null && result.status === 200) category = "HTTP_200_ACCEPTED"
    else if (result.error === null && result.status === 503) {
      let parsedBody = null
      try { parsedBody = JSON.parse(result.body) } catch (_) { parsedBody = null }
      category = parsedBody && parsedBody.error === "AI_CAPACITY_EXCEEDED"
        ? "HTTP_503_ADMISSION"
        : "HTTP_503_DOWNSTREAM"
    }
    else if (result.error === null && result.status === 500) category = "HTTP_500_UNCONTROLLED"
    else if (result.error === null && result.status >= 400 && result.status < 500) category = "HTTP_4XX_DOWNSTREAM"
    else if (result.error === null && result.status >= 500) category = "HTTP_5XX_DOWNSTREAM"
    else if (result.error === null && result.status !== null) category = "HTTP_OTHER"
    else if (result.transport?.category === "CLIENT_ABORT_DEADLINE") category = "CLIENT_TIMEOUT"
    else if (result.transport?.category) category = "CONNECTION_ERROR"
    else if (result.error === "AbortError") category = "CLIENT_TIMEOUT"
    else if (result.error === "TypeError") category = "CONNECTION_ERROR"
    outcomeCategories[category].push(result)
  }

  function latencyStats(items) {
    const values = items.map((item) => item.latencyMs).sort((a, b) => a - b)
    return {
      count: values.length,
      p50: percentile(values, 0.5),
      p95: percentile(values, 0.95),
      p99: percentile(values, 0.99),
      max: values.length ? values[values.length - 1] : null,
    }
  }
  const outcomeCounts = Object.fromEntries(
    Object.entries(outcomeCategories).map(([key, items]) => [key, items.length]),
  )
  const completedClassifiedRequests = Object.values(outcomeCounts).reduce(
    (sum, count) => sum + count,
    0,
  )
  const finalUnfinishedRequests = Math.max(0, startedRequests - results.length)
  const accounting = {
    mode: accountingMode,
    completedClassifiedRequests,
    classifiedTotalMatchesCompleted: completedClassifiedRequests === results.length,
    startedRequests,
    completedAtLoadStop,
    unfinishedAtLoadStop: Math.max(0, startedRequests - completedAtLoadStop),
    inFlightAtLoadStop,
    finalUnfinishedRequests,
    startedMatchesLoadStopAccounting:
      startedRequests === completedAtLoadStop + Math.max(0, startedRequests - completedAtLoadStop),
    startedMatchesFinalAccounting: startedRequests === results.length + finalUnfinishedRequests,
    successTriggeredVuExits,
    prematureVuExits,
    noSuccessTriggeredVuExit: successTriggeredVuExits === 0,
    noPrematureVuExit: prematureVuExits === 0,
    successTriggeredReconnects,
  }
  accounting.valid = Object.entries(accounting)
    .filter(([key]) => key.includes("Matches") || key.startsWith("no"))
    .every(([, value]) => value === true)

  const activatedUserPhases = {}
  for (const result of results) {
    const phase = String(result.activatedUsersAtSchedule || activeMissions)
    if (!activatedUserPhases[phase]) activatedUserPhases[phase] = []
    if (result.error === null) activatedUserPhases[phase].push(result.latencyMs)
  }
  const phaseLatencyMs = Object.fromEntries(
    Object.entries(activatedUserPhases).map(([phase, values]) => {
      const sorted = values.sort((left, right) => left - right)
      return [phase, {
        count: sorted.length,
        p50: percentile(sorted, 0.5),
        p95: percentile(sorted, 0.95),
        p99: percentile(sorted, 0.99),
        max: sorted.length ? sorted[sorted.length - 1] : null,
      }]
    }),
  )

  const successfulRequests = results.filter(
    (result) =>
      result.error === null && result.status >= 200 && result.status < 300,
  ).length
  const failedRequests = results.length - successfulRequests
  const cpuUsage = process.cpuUsage(cpuStarted)
  const memoryUsage = process.memoryUsage()
  eventLoopDelay.disable()

  const summary = {
    experimentRunId,
    implementation,
    startedAt,
    finishedAt: new Date().toISOString(),
    targetUrl: requestUrl.toString(),
    authorizationMode: perVuAuthorizations
      ? "per-vu-token-file"
      : "single-token",
    distinctAuthorizationCount: perVuAuthorizations
      ? perVuAuthorizations.length
      : 1,
    arrivalMode,
    loadScenario,
    accountingMode,
    sendAuthorization,
    sendMissionRunId,
    sendSceneId,
    successMatchMode: successJsonPath ? "json-path" : "literal-true",
    successJsonPath,
    successTriggeredReconnects,
    activeMissions,
    initialActiveUsers,
    activationStepUsers,
    activationIntervalMs,
    reconnectDelayMs,
    intervalMs,
    durationMs,
    loadStoppedAt,
    requestTimeoutMs,
    fixturePath,
    fixtureSource,
    fixtureBytes: fixtureBuffer.length,
    fixtureSha256,
    requestBodyBytes,
    scheduledRequests,
    startedRequests,
    completedRequests: results.length,
    unfinishedRequests: finalUnfinishedRequests,
    successfulRequests,
    failedRequests,
    errorRate:
      results.length === 0 ? null : failedRequests / results.length,
    throughputRequestsPerSecond:
      results.length / (durationMs / 1000),
    maxInFlight,
    completedClassifiedRequests,
    outcomeCounts,
    latencyByOutcome: Object.fromEntries(
      Object.entries(outcomeCategories).map(([key, items]) => [key, latencyStats(items)]),
    ),
    accounting,
    mockDrain,
    statusCounts,
    latencyMs: {
      p50: percentile(latencies, 0.5),
      p90: percentile(latencies, 0.9),
      p95: percentile(latencies, 0.95),
      p99: percentile(latencies, 0.99),
      max: latencies.length ? latencies[latencies.length - 1] : null,
    },
    phaseLatencyMs,
    loadGenerator: {
      cpuUserMs: cpuUsage.user / 1000,
      cpuSystemMs: cpuUsage.system / 1000,
      rssBytes: memoryUsage.rss,
      heapUsedBytes: memoryUsage.heapUsed,
      eventLoopDelayMs: {
        mean: Number(eventLoopDelay.mean) / 1e6,
        p50: Number(eventLoopDelay.percentile(50)) / 1e6,
        p95: Number(eventLoopDelay.percentile(95)) / 1e6,
        p99: Number(eventLoopDelay.percentile(99)) / 1e6,
        max: Number(eventLoopDelay.max) / 1e6,
      },
      runtime: {
        nodeVersion: process.version,
        undiciVersion: process.versions.undici || null,
        platform: process.platform,
        arch: process.arch,
      },
    },
    targetP95Ms,
  }

  if (resultPath) {
    fs.mkdirSync(path.dirname(resultPath), { recursive: true })
    fs.writeFileSync(
      resultPath,
      `${JSON.stringify(
        {
          summary,
          requests: results,
        },
        null,
        2,
      )}\n`,
      "utf8",
    )
  }

  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`)
}

run().catch((error) => {
  process.stderr.write(`${error.stack}\n`)
  process.exitCode = 1
})
