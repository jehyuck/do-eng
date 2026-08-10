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

function runCase(arrivalMode) {
  return new Promise((resolve, reject) => {
    server.listen(0, "127.0.0.1", () => {
      const port = server.address().port
      const resultPath = path.join(tempRoot, `${arrivalMode}.json`)
      const child = spawnSync(process.execPath, [driver], {
        cwd: repositoryRoot,
        env: {
          ...process.env,
          TARGET_URL: `http://127.0.0.1:${port}/game/face`,
          ACTIVE_MISSIONS: "4",
          LOAD_SCENARIO: "reconnect-ramp",
          ARRIVAL_MODE: arrivalMode,
          INITIAL_ACTIVE_USERS: "4",
          ACTIVATION_STEP_USERS: "1",
          ACTIVATION_INTERVAL_MS: "40",
          INTERVAL_MS: "1000",
          DURATION_MS: "180",
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
  const aligned = await runCase("aligned")
  const staggered = await runCase("staggered")
  const initialStarts = (output) =>
    output.requests
      .filter((request) => request.frame === 1)
      .sort((left, right) => left.user - right.user)
      .map((request) => Date.parse(request.requestStartedAt))

  const alignedStarts = initialStarts(aligned)
  const staggeredStarts = initialStarts(staggered)
  assert.strictEqual(alignedStarts.length, 4)
  assert.strictEqual(staggeredStarts.length, 4)
  assert.ok(
    Math.max(...alignedStarts) - Math.min(...alignedStarts) <= 80,
    `aligned starts were not aligned: ${alignedStarts}`,
  )
  assert.ok(
    Math.max(...staggeredStarts) - Math.min(...staggeredStarts) >= 100,
    `staggered starts were not distributed: ${staggeredStarts}`,
  )
  process.stdout.write("reconnect-ramp arrival scheduling test passed\n")
})().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
