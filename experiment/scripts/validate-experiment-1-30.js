const fs = require("fs")
const path = require("path")

const root = path.resolve(process.argv[2] || "backend/experiments/results/experiment-1-30/smoke")
const errors = []
const required = [
  "exp130-run-config.json",
  "admission-before.json",
  "admission-after.json",
  "pool/pool-metrics.jsonl",
  "pool/pool-metrics.jsonl.summary.json",
]

function readJson(relative) {
  const file = path.join(root, relative)
  try { return JSON.parse(fs.readFileSync(file, "utf8").replace(/^\uFEFF/, "")) } catch (error) {
    errors.push(`${relative}: ${error.message}`)
    return null
  }
}

for (const file of required) {
  if (!fs.existsSync(path.join(root, file))) errors.push(`missing: ${file}`)
}

const config = readJson("exp130-run-config.json")
const before = readJson("admission-before.json")
const after = readJson("admission-after.json")
const summary = readJson("pool/pool-metrics.jsonl.summary.json")

if (config) {
  const expected = {
    admissionMode: "OFF", admissionEnabled: false, poolMode: "SHARED",
    sharedPoolMaxConnections: 1000, pendingAcquireMaxCount: 800,
    leasingStrategy: "FIFO", maxIdleTimeMs: 0, evictionIntervalMs: 0,
  }
  for (const [key, value] of Object.entries(expected)) {
    if (config[key] !== value) errors.push(`config mismatch: ${key}`)
  }
}
for (const [label, value] of [["before", before], ["after", after]]) {
  if (value && value.mode !== "OFF") errors.push(`admission ${label} mode is not OFF`)
}
if (summary) {
  if (summary.failures !== 0) errors.push(`collector failures: ${summary.failures}`)
  if (summary.samples < 3) errors.push(`collector samples < 3: ${summary.samples}`)
}

const poolFile = path.join(root, "pool/pool-metrics.jsonl")
if (fs.existsSync(poolFile)) {
  const rows = fs.readFileSync(poolFile, "utf8").split(/\r?\n/).filter(Boolean)
  if (rows.length < 3) errors.push(`pool rows < 3: ${rows.length}`)
  let numeric = 0
  for (const [index, line] of rows.entries()) {
    try {
      const row = JSON.parse(line)
      if (!Array.isArray(row.metrics)) errors.push(`row ${index + 1}: metrics missing`)
      for (const metric of row.metrics || []) {
        if (["active.connections", "idle.connections", "total.connections", "pending.connections"].some(name => String(metric.name).endsWith(name)) && Number.isFinite(Number(metric.value))) numeric++
      }
    } catch (error) { errors.push(`row ${index + 1}: invalid JSON`) }
  }
  if (numeric < 4) errors.push(`numeric pool metric values < 4: ${numeric}`)
}

if (errors.length) {
  console.error(JSON.stringify({ experiment: "Exp130-A", artifactValidation: "FAILED", errors }, null, 2))
  process.exit(1)
}
console.log(JSON.stringify({ experiment: "Exp130-A", artifactValidation: "PASSED", artifactRoot: root }, null, 2))
