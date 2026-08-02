const fs = require("fs")
const path = require("path")
const readline = require("readline")

const runDirectory = path.resolve(process.argv[2] || "")
if (!runDirectory) throw new Error("run directory is required")

function readJson(name) {
  return JSON.parse(fs.readFileSync(path.join(runDirectory, name), "utf8").replace(/^\uFEFF/, ""))
}

function field(text, name) {
  const match = text.match(new RegExp(`${name}=([^,}\\s]+)`))
  if (!match) return null
  const value = match[1].trim()
  return value === "null" || value === "uncommitted" ? null : value
}

function number(value) {
  if (value === null || value === undefined || value === "") return null
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : null
}

function normalizeIp(value) {
  if (!value) return null
  let result = String(value).replace(/^\//, "").replace(/^\[/, "").replace(/\]$/, "")
  result = result.replace(/^::ffff:/i, "")
  const zone = result.indexOf("%")
  if (zone >= 0) result = result.slice(0, zone)
  return result
}

function tuple(localAddress, localPort, remoteAddress, remotePort) {
  const local = normalizeIp(localAddress)
  const remote = normalizeIp(remoteAddress)
  if (!local || !remote || !Number.isFinite(Number(localPort)) || !Number.isFinite(Number(remotePort))) {
    return null
  }
  return `${local}:${Number(localPort)}>${remote}:${Number(remotePort)}`
}

function appTuple(event) {
  return tuple(event.localAddress, event.localPort, event.remoteAddress, event.remotePort)
}

function mockTuple(event) {
  return tuple(event.remoteAddress, event.remotePort, event.localAddress, event.localPort)
}

function endpoint(value) {
  const match = String(value).match(/^(.*)\.(\d+)$/)
  if (!match) return null
  return { address: normalizeIp(match[1]), port: Number(match[2]) }
}

function parsePackets(name, observer) {
  const file = path.join(runDirectory, "capture", name)
  if (!fs.existsSync(file)) return []
  const result = []
  for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    const match = line.match(/^(\d+\.\d+)(?:\s+\S+\s+(?:In|Out))?\s+IP6?\s+(\S+)\s+>\s+(\S+):\s+Flags\s+\[([^\]]+)\](.*)$/)
    if (!match) continue
    const source = endpoint(match[2])
    const destination = endpoint(match[3])
    if (!source || !destination) continue
    const tail = match[5]
    const sequence = (tail.match(/\bseq\s+([^,]+)/) || [])[1] || null
    const acknowledgement = (tail.match(/\back\s+([^,]+)/) || [])[1] || null
    const canonicalTuple = destination.port === 9100
      ? tuple(source.address, source.port, destination.address, destination.port)
      : source.port === 9100
        ? tuple(destination.address, destination.port, source.address, source.port)
        : null
    result.push({
      timestamp: Number(match[1]) * 1000,
      observedAt: new Date(Number(match[1]) * 1000).toISOString(),
      observer,
      sourceAddress: source.address,
      sourcePort: source.port,
      destinationAddress: destination.address,
      destinationPort: destination.port,
      flags: match[4],
      sequence,
      acknowledgement,
      tuple: canonicalTuple,
      sourceActor: source.port === 9100 ? "MOCK" : "APPLICATION",
    })
  }
  return result
}

function firstActor(packets) {
  if (!packets.length) return "NO_CONTROL_PACKET"
  const ordered = [...packets].sort((left, right) => left.timestamp - right.timestamp)
  const first = ordered[0]
  const race = ordered.find((packet) =>
    packet.sourceActor !== first.sourceActor && packet.timestamp === first.timestamp)
  return race ? "BOTH_OR_RACE" : first.sourceActor
}

function uniqueBy(items, key) {
  const seen = new Set()
  return items.filter((item) => {
    const value = key(item)
    if (seen.has(value)) return false
    seen.add(value)
    return true
  })
}

function addToIndex(index, key, value) {
  if (!key) return
  if (!index.has(key)) index.set(key, [])
  index.get(key).push(value)
}

function channelLeaseKey(channelIdLong, leaseSequence) {
  if (!channelIdLong || leaseSequence === null || leaseSequence === undefined) return null
  return `${channelIdLong}|${leaseSequence}`
}

async function main() {
  const client = readJson("client-results.json")
  const baseRows = fs.readFileSync(path.join(runDirectory, "correlation-join.jsonl"), "utf8")
    .split(/\r?\n/).filter(Boolean).map(JSON.parse)
  const mock = readJson("mock-requests.json")
  const runId = client.summary?.experimentRunId || path.basename(runDirectory)
  const bindings = new Map()
  const applicationEvents = []

  const lines = readline.createInterface({
    input: fs.createReadStream(path.join(runDirectory, "application.log"), { encoding: "utf8" }),
    crlfDelay: Infinity,
  })
  for await (const line of lines) {
    if (line.includes("DOENG_REQUEST_CHANNEL_EVENT")) {
      if (field(line, "experimentRunId") !== runId) continue
      const event = {
        timestamp: field(line, "timestamp"),
        event: field(line, "event"),
        requestId: field(line, "experimentRequestId"),
        experimentRunId: field(line, "experimentRunId"),
        missionRunId: field(line, "missionRunId"),
        channelIdShort: field(line, "channelIdShort"),
        channelIdLong: field(line, "channelIdLong"),
        localAddress: field(line, "localAddress"),
        localPort: number(field(line, "localPort")),
        remoteAddress: field(line, "remoteAddress"),
        remotePort: number(field(line, "remotePort")),
        connectionProviderName: field(line, "connectionProviderName"),
        createdAt: field(line, "createdAt"),
        leaseSequence: number(field(line, "leaseSequence")),
        connectionClass: field(line, "connectionClass"),
      }
      applicationEvents.push(event)
      if (event.requestId) bindings.set(event.requestId, event)
    } else if (line.includes("DOENG_CONNECTION_EVENT")) {
      applicationEvents.push({
        timestamp: field(line, "timestamp"),
        stage: field(line, "stage"),
        phase: field(line, "phase"),
        state: field(line, "state"),
        channelIdShort: field(line, "channelIdShort"),
        channelIdLong: field(line, "channelIdLong"),
        localAddress: field(line, "localAddress"),
        localPort: number(field(line, "localPort")),
        remoteAddress: field(line, "remoteAddress"),
        remotePort: number(field(line, "remotePort")),
        connectionProviderName: field(line, "connectionProviderName"),
        createdAt: field(line, "createdAt"),
        leaseSequence: number(field(line, "leaseSequence")),
        connectionClass: field(line, "connectionClass"),
        exceptionClass: field(line, "exceptionClass"),
        rootCauseClass: field(line, "rootCauseClass"),
      })
    }
  }

  const applicationEventsByChannelLease = new Map()
  for (const event of applicationEvents) {
    addToIndex(applicationEventsByChannelLease,
      channelLeaseKey(event.channelIdLong, event.leaseSequence), event)
  }

  const mockEvents = mock.aiLifecycleEvents || []
  const mockRequests = new Map()
  const mockConnectionsByTuple = new Map()
  for (const event of mockEvents) {
    if (event.requestId && (!event.experimentRunId || event.experimentRunId === runId)) {
      if (!mockRequests.has(event.requestId)) mockRequests.set(event.requestId, [])
      mockRequests.get(event.requestId).push(event)
    }
    const key = mockTuple(event)
    if (key) {
      if (!mockConnectionsByTuple.has(key)) mockConnectionsByTuple.set(key, [])
      mockConnectionsByTuple.get(key).push(event)
    }
  }

  const packets = uniqueBy([
    ...parsePackets("application-control.txt", "APPLICATION_NAMESPACE"),
    ...parsePackets("mock-control.txt", "MOCK_NAMESPACE"),
  ], (packet) => [
    Math.round(packet.timestamp), packet.sourceAddress, packet.sourcePort,
    packet.destinationAddress, packet.destinationPort, packet.flags,
    packet.sequence, packet.acknowledgement,
  ].join("|"))
  const packetsByTuple = new Map()
  for (const packet of packets) addToIndex(packetsByTuple, packet.tuple, packet)

  const rows = baseRows.map((base) => {
    const binding = bindings.get(base.requestId) || null
    const applicationSocketTuple = binding ? appTuple(binding) : null
    const requestMockEvents = mockRequests.get(base.requestId) || []
    const mockReceived = requestMockEvents.find((event) => event.event === "MOCK_AI_REQUEST_RECEIVED")
    const mockConnectionCandidates = applicationSocketTuple
      ? (mockConnectionsByTuple.get(applicationSocketTuple) || []) : []
    const mockConnectionIds = [...new Set(mockConnectionCandidates
      .map((event) => event.mockChannelId || event.socketId).filter(Boolean))]
    const bindingAt = binding?.timestamp ? Date.parse(binding.timestamp) : null
    const clientEndAt = base.client?.completedAt ? Date.parse(base.client.completedAt) : null
    const leaseEvents = binding
      ? (applicationEventsByChannelLease.get(
        channelLeaseKey(binding.channelIdLong, binding.leaseSequence)) || [])
      : []
    const channelErrors = leaseEvents.filter((event) =>
      ["PREMATURE_CLOSE", "REQUEST_SEND_ERROR", "RESPONSE_ERROR", "CHANNEL_INACTIVE", "EXCEPTION_CAUGHT"]
        .includes(event.phase))
    const errorAt = channelErrors.map((event) => Date.parse(event.timestamp))
      .filter(Number.isFinite).sort((left, right) => left - right)[0] || null
    const windowEnd = errorAt || clientEndAt || (bindingAt ? bindingAt + 15000 : null)
    const requestPackets = applicationSocketTuple && bindingAt
      ? (packetsByTuple.get(applicationSocketTuple) || []).filter((packet) =>
        packet.timestamp >= bindingAt - 50
        && packet.timestamp <= windowEnd + 2000
        && (packet.flags.includes("F") || packet.flags.includes("R")))
      : []
    const finPackets = requestPackets.filter((packet) => packet.flags.includes("F"))
    const rstPackets = requestPackets.filter((packet) => packet.flags.includes("R"))

    let completeness = "COMPLETE"
    if (!binding) completeness = "MISSING_REQUEST_BINDING"
    else if (!applicationSocketTuple) completeness = "MISSING_SOCKET_TUPLE"
    else if (mockConnectionIds.length > 1) completeness = "AMBIGUOUS_TUPLE"
    else if (mockConnectionIds.length === 0) completeness = "MISSING_MOCK_CONNECTION"
    else if (requestPackets.length === 0) completeness = "MISSING_PACKET"

    return {
      requestId: base.requestId,
      clientOutcome: base.client?.outcome || null,
      inboundStatus: base.inbound?.status ?? null,
      AIStageOutcome: base.aiStage?.failed ? "FAILED" : base.aiStage?.started ? "STARTED_OR_SUCCEEDED" : "NOT_STARTED",
      AIException: base.aiStage?.rootCauseClass || base.aiStage?.throwableClass || null,
      applicationChannelId: binding?.channelIdLong || null,
      applicationSocketTuple,
      leaseSequence: binding?.leaseSequence ?? null,
      connectionClass: binding?.connectionClass || null,
      mockChannelId: mockReceived?.mockChannelId || mockReceived?.socketId || mockConnectionIds[0] || null,
      mockSocketTuple: mockReceived ? mockTuple(mockReceived) : applicationSocketTuple,
      mockHttpRequestReceived: Boolean(mockReceived),
      firstFinSource: firstActor(finPackets),
      firstRstSource: firstActor(rstPackets),
      firstCloseActor: firstActor(requestPackets),
      clientDeadlineAbort: Boolean(base.client?.deadlineAbort),
      channelErrorPhases: [...new Set(channelErrors.map((event) => event.phase))],
      correlationCompleteness: completeness,
    }
  })

  const premature = rows.filter((row) => String(row.AIException).includes("PrematureCloseException"))
  const cancellations = rows.filter((row) => row.clientDeadlineAbort)
  const summary = {
    runId,
    generatedAt: new Date().toISOString(),
    requestCount: rows.length,
    aiPrematureCloseRequests: premature.length,
    newChannelFailures: premature.filter((row) => row.connectionClass === "NEW_CHANNEL").length,
    reusedChannelFailures: premature.filter((row) => row.connectionClass === "REUSED_CHANNEL").length,
    applicationInitiatedClose: premature.filter((row) => row.firstCloseActor === "APPLICATION").length,
    mockInitiatedClose: premature.filter((row) => row.firstCloseActor === "MOCK").length,
    bothOrRaceClose: premature.filter((row) => row.firstCloseActor === "BOTH_OR_RACE").length,
    clientCancellationChains: cancellations.filter((row) =>
      row.firstCloseActor === "APPLICATION" && row.mockHttpRequestReceived).length,
    completeTupleJoins: rows.filter((row) => row.correlationCompleteness === "COMPLETE").length,
    incompleteTupleJoins: rows.filter((row) => row.correlationCompleteness !== "COMPLETE").length,
    prematureCompleteness: premature.reduce((counts, row) => {
      counts[row.correlationCompleteness] = (counts[row.correlationCompleteness] || 0) + 1
      return counts
    }, {}),
    completenessCounts: rows.reduce((counts, row) => {
      counts[row.correlationCompleteness] = (counts[row.correlationCompleteness] || 0) + 1
      return counts
    }, {}),
    capturedPackets: packets.length,
  }

  fs.writeFileSync(path.join(runDirectory, "application-connections.jsonl"),
    `${applicationEvents.map(JSON.stringify).join("\n")}\n`)
  fs.writeFileSync(path.join(runDirectory, "mock-connections.jsonl"),
    `${mockEvents.filter((event) => event.connectionLevel).map(JSON.stringify).join("\n")}\n`)
  fs.writeFileSync(path.join(runDirectory, "connection-correlation.jsonl"),
    `${rows.map(JSON.stringify).join("\n")}\n`)
  fs.writeFileSync(path.join(runDirectory, "connection-correlation-summary.json"),
    `${JSON.stringify(summary, null, 2)}\n`)
  process.stdout.write(`${JSON.stringify(summary)}\n`)
}

main().catch((error) => {
  process.stderr.write(`${error.stack}\n`)
  process.exitCode = 1
})
