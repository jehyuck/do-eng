const fs = require("fs")
const path = require("path")

const runDirectory = path.resolve(process.argv[2] || "")
if (!runDirectory) throw new Error("run directory is required")

const client = JSON.parse(fs.readFileSync(path.join(runDirectory, "client-results.json"), "utf8")
  .replace(/^\uFEFF/, ""))
const measurementStartedAt = Date.parse(client.summary?.startedAt)
const measurementFinishedAt = Date.parse(client.summary?.finishedAt)
const events = fs.readFileSync(path.join(runDirectory, "application-connections.jsonl"), "utf8")
  .split(/\r?\n/).filter(Boolean).map(JSON.parse)
const premature = events.filter((event) =>
  event.stage === "AI"
    && event.phase === "PREMATURE_CLOSE"
    && (!Number.isFinite(measurementStartedAt) || Date.parse(event.timestamp) >= measurementStartedAt)
    && (!Number.isFinite(measurementFinishedAt) || Date.parse(event.timestamp) <= measurementFinishedAt))
const measurementEvents = events.filter((event) =>
  (!Number.isFinite(measurementStartedAt) || Date.parse(event.timestamp) >= measurementStartedAt)
    && (!Number.isFinite(measurementFinishedAt) || Date.parse(event.timestamp) <= measurementFinishedAt))
const configuredLeases = [...new Map(measurementEvents
  .filter((event) => event.state === "[configured]")
  .map((event) => [`${event.channelIdLong}|${event.leaseSequence}`, event])).values()]

function endpoint(value) {
  const separator = value.lastIndexOf(".")
  return { address: value.slice(0, separator), port: Number(value.slice(separator + 1)) }
}

function tuple(appAddress, appPort, mockAddress, mockPort) {
  return `${appAddress}:${appPort}>${mockAddress}:${mockPort}`
}

function readPackets(name) {
  const file = path.join(runDirectory, "capture", name)
  const packets = []
  for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    const match = line.match(/^(\d+\.\d+)(?:\s+\S+\s+(?:In|Out))?\s+IP6?\s+(\S+)\s+>\s+(\S+):\s+Flags\s+\[([^\]]+)\]/)
    if (!match || (!match[4].includes("F") && !match[4].includes("R"))) continue
    const source = endpoint(match[2])
    const destination = endpoint(match[3])
    packets.push({
      timestamp: Number(match[1]) * 1000,
      tuple: source.port === 9100
        ? tuple(destination.address, destination.port, source.address, source.port)
        : tuple(source.address, source.port, destination.address, destination.port),
      actor: source.port === 9100 ? "MOCK" : "APPLICATION",
      flags: match[4],
    })
  }
  return packets
}

const packets = [...readPackets("application-control.txt"), ...readPackets("mock-control.txt")]
const details = premature.map((failure) => {
  const sameChannel = events.filter((event) => event.channelIdLong === failure.channelIdLong)
  const lease = Number(failure.leaseSequence)
  const acquired = sameChannel.find((event) =>
    Number(event.leaseSequence) === lease && event.state === "[acquired]")
  const prepared = sameChannel.find((event) =>
    Number(event.leaseSequence) === lease && event.state === "[request_prepared]")
  const sent = sameChannel.find((event) =>
    Number(event.leaseSequence) === lease && event.state === "[request_sent]")
  const priorRelease = sameChannel.filter((event) =>
    Number(event.leaseSequence) < lease && event.state === "[released]")
    .sort((left, right) => Date.parse(right.timestamp) - Date.parse(left.timestamp))[0]
  const failureAt = Date.parse(failure.timestamp)
  const windowStart = priorRelease ? Date.parse(priorRelease.timestamp) : Date.parse(failure.createdAt)
  const connectionTuple = tuple(
    failure.localAddress, Number(failure.localPort),
    failure.remoteAddress, Number(failure.remotePort))
  const controls = packets.filter((packet) =>
    packet.tuple === connectionTuple
      && packet.timestamp >= windowStart
      && packet.timestamp <= failureAt)
    .sort((left, right) => left.timestamp - right.timestamp)
  const first = controls[0] || null
  return {
    channelIdLong: failure.channelIdLong,
    leaseSequence: lease,
    connectionClass: failure.connectionClass,
    priorReleased: Boolean(priorRelease),
    acquired: Boolean(acquired),
    requestPrepared: Boolean(prepared),
    requestSent: Boolean(sent),
    firstCloseActor: first ? first.actor : "NO_CONTROL_PACKET",
    firstCloseFlags: first ? first.flags : null,
    closeBeforeAcquire: Boolean(first && acquired
      && first.timestamp < Date.parse(acquired.timestamp)),
    closeAfterAcquire: Boolean(first && acquired
      && first.timestamp >= Date.parse(acquired.timestamp)),
    closeToPrematureMs: first ? failureAt - first.timestamp : null,
  }
})

function count(field, value = true) {
  return details.filter((detail) => detail[field] === value).length
}

const summary = {
  generatedAt: new Date().toISOString(),
  runId: client.summary?.experimentRunId || path.basename(runDirectory),
  measurementStartedAt: client.summary?.startedAt || null,
  measurementFinishedAt: client.summary?.finishedAt || null,
  scope: "connection-level only; no request ID is inferred",
  prematureConnectionEvents: details.length,
  newChannelEvents: count("connectionClass", "NEW_CHANNEL"),
  reusedChannelEvents: count("connectionClass", "REUSED_CHANNEL"),
  withPriorRelease: count("priorReleased"),
  withAcquire: count("acquired"),
  withRequestPrepared: count("requestPrepared"),
  withRequestSent: count("requestSent"),
  connectionChurn: {
    distinctChannels: new Set(configuredLeases.map((event) => event.channelIdLong)).size,
    configuredLeases: configuredLeases.length,
    newConnectionLeases: configuredLeases.filter((event) =>
      event.connectionClass === "NEW_CHANNEL").length,
    reusedConnectionLeases: configuredLeases.filter((event) =>
      event.connectionClass === "REUSED_CHANNEL").length,
  },
  firstCloseActor: {
    application: count("firstCloseActor", "APPLICATION"),
    mock: count("firstCloseActor", "MOCK"),
    bothOrRace: count("firstCloseActor", "BOTH_OR_RACE"),
    noControlPacket: count("firstCloseActor", "NO_CONTROL_PACKET"),
  },
  mockCloseBeforeAcquire: details.filter((detail) =>
    detail.firstCloseActor === "MOCK" && detail.closeBeforeAcquire).length,
  mockCloseAfterAcquire: details.filter((detail) =>
    detail.firstCloseActor === "MOCK" && detail.closeAfterAcquire).length,
  requestLevelAttribution: "NOT_CONFIRMED_MISSING_AI_REQUEST_CHANNEL_BOUND",
}

fs.writeFileSync(path.join(runDirectory, "connection-mechanism-details.jsonl"),
  `${details.map(JSON.stringify).join("\n")}\n`)
fs.writeFileSync(path.join(runDirectory, "connection-mechanism-summary.json"),
  `${JSON.stringify(summary, null, 2)}\n`)
process.stdout.write(`${JSON.stringify(summary)}\n`)
