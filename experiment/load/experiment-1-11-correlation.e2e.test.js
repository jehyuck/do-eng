const fs = require("fs")
const path = require("path")

const targetUrl = process.env.TARGET_URL || "http://127.0.0.1:8001/game/face?answer=happy&sceneId=2"
const mockUrl = process.env.MOCK_URL || "http://127.0.0.1:9100"
const outputPath = path.resolve(process.env.RESULT_PATH || "experiment-1-11-e2e-result.json")
const payload = JSON.stringify({ image: "data:image/jpeg;base64,AA==" })

async function control(body) {
  await fetch(`${mockUrl}/__reset`, { method: "POST" })
  const response = await fetch(`${mockUrl}/__control`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ result: false, status: 200, storageDelayMs: 0, ...body }),
  })
  if (!response.ok) throw new Error(`mock control failed: ${response.status}`)
}

function headers(requestId) {
  return {
    Authorization: "Bearer experiment-member-15",
    "Content-Type": "application/json",
    "X-Experiment-Request-Id": requestId,
    "X-Experiment-Run-Id": "EXP111-DETERMINISTIC",
    "X-Mission-Run-Id": `${requestId}-mission`,
  }
}

function post(requestId, signal) {
  return fetch(targetUrl, {
    method: "POST",
    headers: headers(requestId),
    body: payload,
    signal,
  })
}

async function lifecycle(requestId) {
  const artifact = await fetch(`${mockUrl}/__requests`).then((response) => response.json())
  return (artifact.aiLifecycleEvents || []).filter((event) => event.requestId === requestId)
}

function has(events, eventName) {
  return events.some((event) => event.event === eventName)
}

async function normalScenario() {
  const requestId = "exp111-normal"
  await control({ delayMs: 20, closeBeforeResponse: false })
  const response = await post(requestId)
  const body = await response.text()
  const events = await lifecycle(requestId)
  return {
    requestId,
    status: response.status,
    body,
    events,
    valid: response.status === 200
      && body === "false"
      && has(events, "MOCK_AI_REQUEST_RECEIVED")
      && has(events, "MOCK_AI_RESPONSE_WRITE_STARTED")
      && has(events, "MOCK_AI_RESPONSE_FINISHED"),
  }
}

async function forcedCloseScenario() {
  const requestId = "exp111-forced-close"
  await control({ delayMs: 20, closeBeforeResponse: true })
  const response = await post(requestId)
  await response.text()
  await new Promise((resolve) => setTimeout(resolve, 100))
  const events = await lifecycle(requestId)
  return {
    requestId,
    status: response.status,
    events,
    valid: response.status === 500
      && has(events, "MOCK_AI_REQUEST_RECEIVED")
      && !has(events, "MOCK_AI_RESPONSE_FINISHED")
      && events.some((event) => event.event === "MOCK_AI_RESPONSE_CLOSED" && event.incompleteResponse),
  }
}

async function cancellationScenario() {
  const requestId = "exp111-client-cancel"
  await control({ delayMs: 1000, closeBeforeResponse: false })
  const controller = new AbortController()
  const request = post(requestId, controller.signal)
  await new Promise((resolve) => setTimeout(resolve, 100))
  const abortedAt = new Date().toISOString()
  controller.abort()
  try { await request } catch (_) {}
  await new Promise((resolve) => setTimeout(resolve, 200))
  const events = await lifecycle(requestId)
  const close = events.find((event) =>
    event.event === "MOCK_AI_REQUEST_ABORTED" ||
    (event.event === "MOCK_AI_RESPONSE_CLOSED" && event.incompleteResponse))
  return {
    requestId,
    abortedAt,
    events,
    valid: has(events, "MOCK_AI_REQUEST_RECEIVED")
      && Boolean(close)
      && Date.parse(close.observedAt) >= Date.parse(abortedAt),
  }
}

async function admissionScenario() {
  const heldId = "exp111-admission-held"
  const rejectedId = "exp111-admission-rejected"
  await control({ delayMs: 1000, closeBeforeResponse: false })
  const heldController = new AbortController()
  const held = post(heldId, heldController.signal)
  await new Promise((resolve) => setTimeout(resolve, 150))
  const rejected = await post(rejectedId)
  await rejected.text()
  heldController.abort()
  try { await held } catch (_) {}
  await new Promise((resolve) => setTimeout(resolve, 100))
  const rejectedEvents = await lifecycle(rejectedId)
  return {
    requestId: rejectedId,
    status: rejected.status,
    mockEvents: rejectedEvents,
    valid: rejected.status === 503 && rejectedEvents.length === 0,
  }
}

async function main() {
  const result = {
    generatedAt: new Date().toISOString(),
    normal: await normalScenario(),
    forcedClose: await forcedCloseScenario(),
    cancellation: await cancellationScenario(),
    admission: await admissionScenario(),
  }
  result.valid = result.normal.valid
    && result.forcedClose.valid
    && result.cancellation.valid
    && result.admission.valid
  fs.writeFileSync(outputPath, `${JSON.stringify(result, null, 2)}\n`)
  process.stdout.write(`${JSON.stringify({ valid: result.valid })}\n`)
  if (!result.valid) process.exitCode = 1
}

main().catch((error) => {
  process.stderr.write(`${error.stack}\n`)
  process.exitCode = 1
})
