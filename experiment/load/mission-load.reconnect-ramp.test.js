const assert = require("assert")
const fs = require("fs")
const http = require("http")
const os = require("os")
const path = require("path")
const { spawnSync } = require("child_process")

const repositoryRoot = path.resolve(__dirname, "../..")
const driver = path.join(__dirname, "mission-load.js")
const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "doeng-reconnect-ramp-"))
const fixturePath = path.join(tempRoot, "fixture.jpg")
fs.writeFileSync(fixturePath, Buffer.from("deterministic-fixture"))

const server = http.createServer((request, response) => {
  request.resume()
  request.on("end", () => {
    response.statusCode = 200
    response.end("false")
  })
})

function runCase({ arrivalMode, activeMissions = 4, initialActiveUsers = 4, activationStepUsers = 1, activationIntervalMs = 100, durationMs = 180 }) {
  return new Promise((resolve, reject) => {
    server.listen(0, "127.0.0.1", () => {
      const port = server.address().port
      const resultPath = path.join(tempRoot, `${arrivalMode}.json`)
      const child = spawnSync(process.execPath, [driver], {
        cwd: repositoryRoot,
        env: {
          ...process.env,
          TARGET_URL: `http://127.0.0.1:${port}/game/face`,
          ACTIVE_MISSIONS: String(activeMissions),
          LOAD_SCENARIO: "reconnect-ramp",
          ARRIVAL_MODE: arrivalMode,
          INITIAL_ACTIVE_USERS: String(initialActiveUsers),
          ACTIVATION_STEP_USERS: String(activationStepUsers),
          ACTIVATION_INTERVAL_MS: String(activationIntervalMs),
          INTERVAL_MS: "1000",
          DURATION_MS: String(durationMs),
          REQUEST_TIMEOUT_MS: "1000",
          RECONNECT_DELAY_MS: "1000",
          FIXTURE_PATH: fixturePath,
          STOP_USER_ON_TRUE: "false",
          RESULT_PATH: resultPath,
          EXPERIMENT_RUN_ID: `TEST-RECONNECT-${arrivalMode}`,
          IMPLEMENTATION: "test",
        },
        encoding: "utf8",
      })
      server.close(() => {
        if (child.status !== 0) {
          reject(new Error(child.stderr || child.stdout))
          return
        }
        resolve(JSON.parse(fs.readFileSync(resultPath, "utf8")))
      })
    })
  })
}

;(async () => {
  const aligned = await runCase({ arrivalMode: "aligned" })
  const staggered = await runCase({ arrivalMode: "staggered" })
  const staged = await runCase({
    arrivalMode: "staggered",
    activeMissions: 4,
    initialActiveUsers: 2,
    activationStepUsers: 1,
    activationIntervalMs: 100,
    durationMs: 280,
  })
  const initialStarts = (output) =>
    output.requests
      .filter((request) => request.frame === 1)
      .sort((left, right) => left.user - right.user)
      .map((request) => ({
        stage: request.activationStage,
        time: Date.parse(request.requestStartedAt),
      }))

  const alignedStarts = initialStarts(aligned)
  const staggeredStarts = initialStarts(staggered)
  const stagedStarts = initialStarts(staged)
  assert.strictEqual(alignedStarts.length, 4)
  assert.strictEqual(staggeredStarts.length, 4)
  assert.strictEqual(stagedStarts.length, 4)
  assert.ok(
    Math.max(...alignedStarts.map(({ time }) => time)) -
        Math.min(...alignedStarts.map(({ time }) => time)) <=
      80,
    `aligned starts were not aligned: ${alignedStarts}`,
  )
  assert.ok(
    Math.max(...staggeredStarts.map(({ time }) => time)) -
        Math.min(...staggeredStarts.map(({ time }) => time)) >=
      50 &&
      Math.max(...staggeredStarts.map(({ time }) => time)) -
        Math.min(...staggeredStarts.map(({ time }) => time)) <
        100,
    `staggered starts were not distributed: ${staggeredStarts}`,
  )
  const stageZero = stagedStarts.filter(({ stage }) => stage === 0)
  const stageOne = stagedStarts.filter(({ stage }) => stage === 1)
  const stageTwo = stagedStarts.filter(({ stage }) => stage === 2)
  assert.strictEqual(stageZero.length, 2)
  assert.strictEqual(stageOne.length, 1)
  assert.strictEqual(stageTwo.length, 1)
  assert.ok(stageOne[0].time - stageZero[0].time >= 70)
  assert.ok(stageTwo[0].time - stageOne[0].time >= 70)
  process.stdout.write("reconnect-ramp arrival scheduling test passed\n")
})().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
