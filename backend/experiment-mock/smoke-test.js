const assert = require("assert")
const path = require("path")
const { spawn } = require("child_process")

const workingDirectory = __dirname
const server = spawn(process.execPath, [path.join(workingDirectory, "server.js")], {
  cwd: workingDirectory,
  env: {
    ...process.env,
    MOCK_PORT: "19100",
    MOCK_MEMBER_ID: "15",
  },
  stdio: "ignore",
})

async function waitUntilReady() {
  for (let attempt = 0; attempt < 30; attempt += 1) {
    try {
      const response = await fetch("http://127.0.0.1:19100/health")
      if (response.ok) return
    } catch (error) {
      // The child process may still be starting.
    }
    await new Promise((resolve) => setTimeout(resolve, 100))
  }
  throw new Error("experiment mock did not become ready")
}

async function run() {
  await waitUntilReady()

  const authResponse = await fetch("http://127.0.0.1:19100/api/member/ai", {
    headers: {
      Authorization: "Bearer experiment-member-27",
    },
  })
  assert.strictEqual(authResponse.status, 200)
  assert.deepStrictEqual(await authResponse.json(), { id: 27 })

  const controlResponse = await fetch("http://127.0.0.1:19100/__control", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      result: true,
      delayMs: 0,
      status: 200,
    }),
  })
  assert.strictEqual(controlResponse.status, 200)

  const aiResponse = await fetch("http://127.0.0.1:19100/analyze/face", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      answer: "happy",
      image: "data:image/jpeg;base64,aGVsbG8=",
    }),
  })
  assert.strictEqual(aiResponse.status, 200)
  assert.deepStrictEqual(await aiResponse.json(), {
    result: true,
    image: "aGVsbG8=",
  })

  const noEchoControlResponse = await fetch("http://127.0.0.1:19100/__control", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ echoImage: false }),
  })
  assert.strictEqual(noEchoControlResponse.status, 200)

  const noEchoAiResponse = await fetch("http://127.0.0.1:19100/analyze/face", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      answer: "happy",
      image: "data:image/jpeg;base64,aGVsbG8=",
    }),
  })
  assert.strictEqual(noEchoAiResponse.status, 200)
  assert.deepStrictEqual(await noEchoAiResponse.json(), { result: true })

  const requestsResponse = await fetch("http://127.0.0.1:19100/__requests")
  assert.strictEqual(requestsResponse.status, 200)
  const requests = await requestsResponse.json()
  assert.deepStrictEqual(requests.counts, {
    "GET /api/member/ai": 1,
    "POST /analyze/face": 2,
  })
  assert.strictEqual(requests.requests.length, 3)
}

run()
  .then(() => {
    process.stdout.write("experiment mock smoke test passed\n")
  })
  .catch((error) => {
    process.stderr.write(`${error.stack}\n`)
    process.exitCode = 1
  })
  .finally(() => {
    server.kill()
  })
