#!/usr/bin/env node

// Validates that the rendered Compose configurations differ only by the
// preregistered Experiment 1-19 lifecycle-policy environment variables.
// It is intentionally a provenance check, not a performance analyzer.

const fs = require("fs")
const path = require("path")

function usage() {
  throw new Error(
    "Usage: node verify-experiment-1-19-controlled-diff.js <baseline-compose.json> <remediation-compose.json> <baseline-runtime.json> <remediation-runtime.json> <result.json> <diff.txt>"
  )
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8").replace(/^\uFEFF/, ""))
}

function environmentMap(environment) {
  if (Array.isArray(environment)) {
    return Object.fromEntries(environment.map((value) => {
      const separator = String(value).indexOf("=")
      return separator < 0
        ? [String(value), ""]
        : [String(value).slice(0, separator), String(value).slice(separator + 1)]
    }))
  }
  return { ...(environment || {}) }
}

function normalizedCompose(input) {
  const copy = JSON.parse(JSON.stringify(input))
  delete copy.name
  const service = copy.services && copy.services["flux-corrected"]
  if (!service) {
    throw new Error("Rendered Compose configuration has no flux-corrected service")
  }
  const environment = environmentMap(service.environment)
  for (const key of Object.keys(expected.baseline)) {
    delete environment[key]
  }
  service.environment = environment
  return copy
}

const expected = {
  baseline: {
    DOENG_EXTERNAL_LEASING_STRATEGY: "FIFO",
    DOENG_EXTERNAL_MAX_IDLE_TIME_MS: "0",
    DOENG_EXTERNAL_EVICTION_INTERVAL_MS: "0",
  },
  remediation: {
    DOENG_EXTERNAL_LEASING_STRATEGY: "LIFO",
    DOENG_EXTERNAL_MAX_IDLE_TIME_MS: "3000",
    DOENG_EXTERNAL_EVICTION_INTERVAL_MS: "1000",
  },
}

function runtimeSnapshot(input) {
  const runtime = input.runtimePropertyProof || {}
  const environment = runtime.containerEnvironment || {}
  return {
    poolMode: runtime.actuatorPoolMode ?? null,
    DOENG_EXTERNAL_LEASING_STRATEGY: environment.DOENG_EXTERNAL_LEASING_STRATEGY ?? null,
    DOENG_EXTERNAL_MAX_IDLE_TIME_MS: environment.DOENG_EXTERNAL_MAX_IDLE_TIME_MS ?? null,
    DOENG_EXTERNAL_EVICTION_INTERVAL_MS: environment.DOENG_EXTERNAL_EVICTION_INTERVAL_MS ?? null,
    DOENG_SHARED_POOL_MAX_CONNECTIONS: environment.DOENG_SHARED_POOL_MAX_CONNECTIONS ?? null,
    DOENG_SHARED_POOL_PENDING_MAX_COUNT: environment.DOENG_SHARED_POOL_PENDING_MAX_COUNT ?? null,
    DOENG_HTTP_PENDING_ACQUIRE_TIMEOUT_MS: environment.DOENG_HTTP_PENDING_ACQUIRE_TIMEOUT_MS ?? null,
    DOENG_HTTP_CONNECT_TIMEOUT_MS: environment.DOENG_HTTP_CONNECT_TIMEOUT_MS ?? null,
    DOENG_HTTP_RESPONSE_TIMEOUT_MS: environment.DOENG_HTTP_RESPONSE_TIMEOUT_MS ?? null,
    DOENG_AI_ADMISSION_MAX_CONCURRENT: environment.DOENG_AI_ADMISSION_MAX_CONCURRENT ?? null,
  }
}

if (process.argv.length !== 8) usage()
const [, , baselinePath, remediationPath, baselineRuntimePath, remediationRuntimePath, resultPath, diffPath] = process.argv
const baseline = readJson(baselinePath)
const remediation = readJson(remediationPath)
const baselineRuntime = runtimeSnapshot(readJson(baselineRuntimePath))
const remediationRuntime = runtimeSnapshot(readJson(remediationRuntimePath))
const baselineService = baseline.services && baseline.services["flux-corrected"]
const remediationService = remediation.services && remediation.services["flux-corrected"]
if (!baselineService || !remediationService) {
  throw new Error("One rendered Compose configuration is missing flux-corrected")
}

const baselineEnvironment = environmentMap(baselineService.environment)
const remediationEnvironment = environmentMap(remediationService.environment)
const observed = {
  baseline: Object.fromEntries(Object.keys(expected.baseline).map((key) => [key, baselineEnvironment[key] ?? null])),
  remediation: Object.fromEntries(Object.keys(expected.remediation).map((key) => [key, remediationEnvironment[key] ?? null])),
}
const valuesMatch = JSON.stringify(observed) === JSON.stringify(expected)
const canonicalMatch = JSON.stringify(normalizedCompose(baseline)) === JSON.stringify(normalizedCompose(remediation))
const normalizedBaselineRuntime = { ...baselineRuntime }
const normalizedRemediationRuntime = { ...remediationRuntime }
for (const key of Object.keys(expected.baseline)) {
  delete normalizedBaselineRuntime[key]
  delete normalizedRemediationRuntime[key]
}
const runtimePolicyValuesMatch = Object.entries(expected.baseline).every(([key, value]) =>
  baselineRuntime[key] === value && remediationRuntime[key] === expected.remediation[key]
)
const runtimeFixedValuesMatch = JSON.stringify(normalizedBaselineRuntime) === JSON.stringify(normalizedRemediationRuntime)
const result = {
  checkedAt: new Date().toISOString(),
  expected,
  observed,
  valuesMatch,
  canonicalComposeMatchAfterRemovingPolicyFields: canonicalMatch,
  runtime: { baseline: baselineRuntime, remediation: remediationRuntime, policyValuesMatch: runtimePolicyValuesMatch, fixedValuesMatch: runtimeFixedValuesMatch },
  controlledDiffValid: valuesMatch && canonicalMatch && runtimePolicyValuesMatch && runtimeFixedValuesMatch,
}

fs.mkdirSync(path.dirname(resultPath), { recursive: true })
fs.writeFileSync(resultPath, `${JSON.stringify(result, null, 2)}\n`)
fs.writeFileSync(diffPath, [
  "Experiment 1-19 controlled Compose diff",
  `policy values match preregistration: ${valuesMatch}`,
  `all remaining rendered Compose content identical: ${canonicalMatch}`,
  `runtime lifecycle values match preregistration: ${runtimePolicyValuesMatch}`,
  `all remaining runtime values identical: ${runtimeFixedValuesMatch}`,
  "baseline:",
  ...Object.entries(observed.baseline).map(([key, value]) => `  ${key}=${value}`),
  "remediation:",
  ...Object.entries(observed.remediation).map(([key, value]) => `  ${key}=${value}`),
  "",
].join("\n"))

if (!result.controlledDiffValid) process.exitCode = 1
