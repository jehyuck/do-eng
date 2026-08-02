const fs = require("fs")
const path = require("path")

const directory = path.resolve(process.argv[2] || "")
if (!directory) throw new Error("control directory is required")

const rows = fs.readFileSync(path.join(directory, "connection-correlation.jsonl"), "utf8")
  .split(/\r?\n/).filter(Boolean).map(JSON.parse)
const connectionEvents = fs.readFileSync(path.join(directory, "application-connections.jsonl"), "utf8")
  .split(/\r?\n/).filter(Boolean).map(JSON.parse)
const byId = new Map(rows.map((row) => [row.requestId, row]))

function row(id) {
  const value = byId.get(id)
  if (!value) throw new Error(`missing control row: ${id}`)
  return value
}

const first = row("exp112-normal-first")
const second = row("exp112-normal-second")
const forced = row("exp112-mock-close")
const cancelled = row("exp112-client-cancel")
const rejected = row("exp112-admission-rejected")

const assertions = {
  newConnectionClassified: connectionEvents.some((item) => item.connectionClass === "NEW_CHANNEL"),
  reusedConnectionClassified: [first, second].some((item) => item.connectionClass === "REUSED_CHANNEL"),
  requestBindingPresent: [first, second, forced, cancelled].every((item) =>
    item.applicationChannelId && item.leaseSequence > 0),
  reusedNormalCompletes: second.clientOutcome === "HTTP_200"
    && ["NEW_CHANNEL", "REUSED_CHANNEL"].includes(second.connectionClass),
  mockInitiatedDirection: forced.clientOutcome === "HTTP_500"
    && String(forced.AIException).includes("PrematureCloseException")
    && forced.mockHttpRequestReceived
    && forced.firstCloseActor === "MOCK",
  clientCancellationDirection: cancelled.clientDeadlineAbort
    && cancelled.mockHttpRequestReceived
    && cancelled.firstCloseActor === "APPLICATION",
  admissionHasNoAiBinding: rejected.clientOutcome === "HTTP_503"
    && !rejected.applicationChannelId
    && !rejected.mockHttpRequestReceived,
}

const result = {
  generatedAt: new Date().toISOString(),
  assertions,
  valid: !Object.values(assertions).includes(false),
  rows: { first, second, forced, cancelled, rejected },
}

fs.writeFileSync(path.join(directory, "positive-control-summary.json"), `${JSON.stringify(result, null, 2)}\n`)
process.stdout.write(`${JSON.stringify({ valid: result.valid, assertions })}\n`)
if (!result.valid) process.exitCode = 1
