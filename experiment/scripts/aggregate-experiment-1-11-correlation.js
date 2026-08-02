const fs = require("fs")
const path = require("path")
const readline = require("readline")

const runDirectory = path.resolve(process.argv[2] || "")
if (!runDirectory) throw new Error("run directory is required")

const clientArtifact = JSON.parse(
  fs.readFileSync(path.join(runDirectory, "client-results.json"), "utf8").replace(/^\uFEFF/, ""),
)
const mockArtifact = JSON.parse(
  fs.readFileSync(path.join(runDirectory, "mock-requests.json"), "utf8").replace(/^\uFEFF/, ""),
)
const expectedRunId = clientArtifact.summary?.experimentRunId || path.basename(runDirectory)

const joined = new Map()
const connectionEvents = []

function row(requestId) {
  if (!joined.has(requestId)) {
    joined.set(requestId, {
      requestId,
      client: null,
      inboundEvents: [],
      responseEvent: null,
      stageEvents: [],
      mockEvents: [],
    })
  }
  return joined.get(requestId)
}

function field(text, name) {
  const match = text.match(new RegExp(`${name}=([^,}\\s]+)`))
  if (!match) return null
  const value = match[1].trim()
  return value === "null" || value === "uncommitted" ? null : value
}

function numberOrNull(value) {
  if (value === null || value === undefined || value === "") return null
  const number = Number(value)
  return Number.isFinite(number) ? number : null
}

function clientOutcome(request) {
  if (request.status !== null) return `HTTP_${request.status}`
  return request.transport?.category || request.error || "UNKNOWN"
}

for (const request of clientArtifact.requests || []) {
  row(request.requestId).client = {
    outcome: clientOutcome(request),
    status: request.status,
    deadlineAbort: request.transport?.category === "CLIENT_ABORT_DEADLINE",
    requestStartedAt: request.requestStartedAt || null,
    completedAt: request.completedAt || null,
  }
}

for (const event of mockArtifact.aiLifecycleEvents || []) {
  if (!event.requestId) {
    connectionEvents.push(event)
    continue
  }
  if (event.experimentRunId && event.experimentRunId !== expectedRunId) continue
  row(event.requestId).mockEvents.push(event)
}

async function readApplicationLog() {
  const stream = fs.createReadStream(path.join(runDirectory, "application.log"), { encoding: "utf8" })
  const lines = readline.createInterface({ input: stream, crlfDelay: Infinity })
  for await (const line of lines) {
    if (line.includes("DOENG_INBOUND_EVENT")) {
      if (field(line, "runId") !== expectedRunId) continue
      const requestId = field(line, "requestId")
      if (!requestId) continue
      row(requestId).inboundEvents.push({
        event: field(line, "phase"),
        timestamp: field(line, "timestamp"),
        status: numberOrNull(field(line, "status")),
        committed: field(line, "committed") === "true",
        signalError: field(line, "signalError"),
      })
    } else if (line.includes("DOENG_STAGE_EVENT")) {
      if (field(line, "runId") !== expectedRunId) continue
      const requestId = field(line, "requestId")
      if (!requestId) continue
      row(requestId).stageEvents.push({
        event: field(line, "event"),
        timestamp: field(line, "timestamp"),
        stage: field(line, "stage"),
        throwableClass: field(line, "throwableClass"),
        rootCauseClass: field(line, "rootCauseClass"),
      })
    } else if (line.includes("experiment_request")) {
      if (field(line, "runId") !== expectedRunId) continue
      const requestId = field(line, "requestId")
      if (!requestId) continue
      row(requestId).responseEvent = {
        status: numberOrNull(field(line, "status")),
        terminalSignal: field(line, "signal"),
      }
    }
  }
}

function duplicateCount(events) {
  const counts = new Map()
  for (const event of events) counts.set(event.event, (counts.get(event.event) || 0) + 1)
  return Array.from(counts.values()).filter((count) => count > 1)
    .reduce((sum, count) => sum + count - 1, 0)
}

function normalize(item) {
  const inboundReceived = item.inboundEvents.find((event) => event.event === "RECEIVED")
  const inboundTerminal = [...item.inboundEvents]
    .reverse()
    .find((event) => event.event === "TERMINAL" || event.event === "CANCELLED")
  const aiEvents = item.stageEvents.filter((event) => event.stage === "AI")
  const aiStarted = aiEvents.find((event) => event.event === "STAGE_STARTED")
  const aiFailed = aiEvents.find((event) => event.event === "STAGE_FAILED")
  const mockReceived = item.mockEvents.find((event) => event.event === "MOCK_AI_REQUEST_RECEIVED")
  const mockWrite = item.mockEvents.find((event) => event.event === "MOCK_AI_RESPONSE_WRITE_STARTED")
  const mockFinished = item.mockEvents.find((event) => event.event === "MOCK_AI_RESPONSE_FINISHED")
  const mockAborted = item.mockEvents.find((event) => event.event === "MOCK_AI_REQUEST_ABORTED")
  const mockClosed = item.mockEvents.find((event) => event.event === "MOCK_AI_RESPONSE_CLOSED")
  const duplicateCallbacks = duplicateCount(item.inboundEvents)
    + duplicateCount(aiEvents)
    + duplicateCount(item.mockEvents)

  const controlledRejection = item.client?.status === 503 && !aiStarted && !mockReceived
  let completeness = "COMPLETE"
  if (duplicateCallbacks > 0) completeness = "AMBIGUOUS_DUPLICATE"
  else if (!item.client) completeness = "MISSING_CLIENT"
  else if (!inboundReceived) completeness = "MISSING_INBOUND"
  else if (!controlledRejection && !aiStarted) completeness = "MISSING_AI_STAGE"
  else if (!controlledRejection && !mockReceived) completeness = "MISSING_MOCK"

  const clientCompletedAt = item.client?.completedAt ? Date.parse(item.client.completedAt) : null
  const mockAbortAt = mockAborted?.observedAt ? Date.parse(mockAborted.observedAt) : null

  return {
    requestId: item.requestId,
    client: item.client,
    inbound: {
      received: Boolean(inboundReceived),
      terminalSignal: item.responseEvent?.terminalSignal || inboundTerminal?.event || null,
      status: item.responseEvent?.status ?? inboundTerminal?.status ?? null,
      signalError: inboundTerminal?.signalError || null,
    },
    aiStage: {
      started: Boolean(aiStarted),
      failed: Boolean(aiFailed),
      throwableClass: aiFailed?.throwableClass || null,
      rootCauseClass: aiFailed?.rootCauseClass || null,
    },
    mock: {
      received: Boolean(mockReceived),
      responseWriteStarted: Boolean(mockWrite),
      responseFinished: Boolean(mockFinished),
      requestAborted: Boolean(mockAborted),
      incompleteResponse: Boolean(mockClosed?.incompleteResponse),
    },
    duplicateCallbacks,
    clientAbortPrecededMockAbort:
      Boolean(item.client?.deadlineAbort && clientCompletedAt && mockAbortAt && clientCompletedAt <= mockAbortAt),
    correlationCompleteness: completeness,
  }
}

async function main() {
  await readApplicationLog()
  const rows = Array.from(joined.values()).map(normalize)
    .sort((left, right) => left.requestId.localeCompare(right.requestId))
  const summary = {
    runId: clientArtifact.summary?.experimentRunId || path.basename(runDirectory),
    generatedAt: new Date().toISOString(),
    requestCount: rows.length,
    http500Requests: rows.filter((item) => item.client?.status === 500).length,
    clientTimeoutRequests: rows.filter((item) => item.client?.deadlineAbort).length,
    aiPrematureCloseRequests: rows.filter((item) =>
      String(item.aiStage.rootCauseClass || item.aiStage.throwableClass).includes("PrematureCloseException"),
    ).length,
    completeCorrelations: rows.filter((item) => item.correlationCompleteness === "COMPLETE").length,
    incompleteCorrelations: rows.filter((item) => item.correlationCompleteness !== "COMPLETE").length,
    mockIncompleteResponses: rows.filter((item) => item.mock.incompleteResponse).length,
    clientAbortPreceded: rows.filter((item) => item.clientAbortPrecededMockAbort).length,
    duplicateCallbacks: rows.reduce((sum, item) => sum + item.duplicateCallbacks, 0),
    connectionEvents: connectionEvents.length,
    completenessCounts: rows.reduce((counts, item) => {
      counts[item.correlationCompleteness] = (counts[item.correlationCompleteness] || 0) + 1
      return counts
    }, {}),
  }
  fs.writeFileSync(
    path.join(runDirectory, "correlation-join.jsonl"),
    `${rows.map((item) => JSON.stringify(item)).join("\n")}\n`,
  )
  fs.writeFileSync(
    path.join(runDirectory, "correlation-summary.json"),
    `${JSON.stringify(summary, null, 2)}\n`,
  )
  fs.writeFileSync(
    path.join(runDirectory, "connection-events.jsonl"),
    `${connectionEvents.map((item) => JSON.stringify(item)).join("\n")}\n`,
  )
  process.stdout.write(`${JSON.stringify(summary)}\n`)
}

main().catch((error) => {
  process.stderr.write(`${error.stack}\n`)
  process.exitCode = 1
})
