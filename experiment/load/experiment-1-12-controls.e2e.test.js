const fs = require("fs")
const path = require("path")

const targetUrl = process.env.TARGET_URL || "http://127.0.0.1:8001/game/face?answer=happy&sceneId=2"
const mockUrl = process.env.MOCK_URL || "http://127.0.0.1:9100"
const outputPath = path.resolve(process.env.RESULT_PATH || "experiment-1-12-controls.json")
const payload = JSON.stringify({ image: "data:image/jpeg;base64,AA==" })
const runId = "EXP112-CONTROL"

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
    "X-Experiment-Run-Id": runId,
    "X-Mission-Run-Id": `${requestId}-mission`,
  }
}

async function post(requestId, signal) {
  const requestStartedAt = new Date().toISOString()
  try {
    const response = await fetch(targetUrl, {
      method: "POST", headers: headers(requestId), body: payload, signal,
    })
    const body = await response.text()
    return { requestId, status: response.status, body, requestStartedAt, completedAt: new Date().toISOString() }
  } catch (error) {
    return {
      requestId,
      status: null,
      error: error.name,
      transport: { category: error.name === "AbortError" ? "CLIENT_ABORT_DEADLINE" : "CONNECTION_ERROR" },
      requestStartedAt,
      completedAt: new Date().toISOString(),
    }
  }
}

async function allLifecycle() {
  return fetch(`${mockUrl}/__requests`).then((response) => response.json())
}

async function normalReuse() {
  await control({ delayMs: 20, closeBeforeResponse: false })
  const first = await post("exp112-normal-first")
  const second = await post("exp112-normal-second")
  return { requests: [first, second], artifact: await allLifecycle() }
}

async function mockClose() {
  await control({ delayMs: 20, closeBeforeResponse: true })
  const request = await post("exp112-mock-close")
  await new Promise((resolve) => setTimeout(resolve, 150))
  return { requests: [request], artifact: await allLifecycle() }
}

async function clientCancel() {
  await control({ delayMs: 1000, closeBeforeResponse: false })
  const controller = new AbortController()
  const pending = post("exp112-client-cancel", controller.signal)
  await new Promise((resolve) => setTimeout(resolve, 100))
  controller.abort()
  const request = await pending
  await new Promise((resolve) => setTimeout(resolve, 250))
  return { requests: [request], artifact: await allLifecycle() }
}

async function admission() {
  await control({ delayMs: 1000, closeBeforeResponse: false })
  const controller = new AbortController()
  const held = post("exp112-admission-held", controller.signal)
  await new Promise((resolve) => setTimeout(resolve, 150))
  const rejected = await post("exp112-admission-rejected")
  controller.abort()
  await held
  await new Promise((resolve) => setTimeout(resolve, 150))
  return { requests: [rejected], artifact: await allLifecycle() }
}

async function main() {
  const scenarios = {
    normalReuse: await normalReuse(),
    mockClose: await mockClose(),
    clientCancel: await clientCancel(),
    admission: await admission(),
  }
  const requests = Object.values(scenarios).flatMap((scenario) => scenario.requests)
  const aiLifecycleEvents = Object.values(scenarios)
    .flatMap((scenario) => scenario.artifact.aiLifecycleEvents || [])
  const result = { generatedAt: new Date().toISOString(), runId, scenarios, requests, aiLifecycleEvents }
  fs.writeFileSync(outputPath, `${JSON.stringify(result, null, 2)}\n`)
  process.stdout.write(`${JSON.stringify({ requestCount: requests.length })}\n`)
}

main().catch((error) => {
  process.stderr.write(`${error.stack}\n`)
  process.exitCode = 1
})
