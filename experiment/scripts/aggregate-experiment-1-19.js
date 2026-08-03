#!/usr/bin/env node

// Schema-only preparation for Experiment 1-19.  This does not read, create,
// or aggregate core performance results.  Core execution is intentionally
// outside the preflight task.

const fs = require("fs")
const path = require("path")

if (process.argv.length !== 3 && process.argv.length !== 5) {
  throw new Error("Usage: node aggregate-experiment-1-19.js <schema-output.json> | --readiness <core-root> <output.json>")
}

const schema = {
  experiment: "Experiment 1-19",
  purpose: "Fresh-First lifecycle-policy A/B core result schema",
  executionStatus: "NOT_RUN",
  arms: ["BASELINE", "REMEDIATION"],
  requiredValidCoreRunsPerArm: 3,
  requiredArtifactsPerRun: [
    "run-config.json",
    "client-results.json",
    "client-progress.jsonl",
    "pool/pool-metrics.jsonl",
    "application/application.log",
    "database/",
    "container/",
    "mock/load-stop-mock-metrics.json",
    "drain/mock-drain-summary.json",
    "verification-summary.json",
    "provenance/",
  ],
  validity: ["measurementValidity", "condition", "runId", "sourceCommit", "imageIdOrDigest", "configSnapshot", "renderedComposeHash", "fixtureAuthResetConsistency", "collectorCompleteness", "loadStopDrainCompleteness"],
  primaryReliability: ["aiPrematureCloseTotal", "reusedChannelPrematureClose", "mockCloseBeforeAcquireReusedPrematureClose", "aiTransportHttp500", "duplicateMockHandlerCount", "uncontrolledFailure"],
  guardrail: ["http200Median", "acceptedRequestP95Median", "successfulCompletion", "connectionCreation", "activeIdlePending", "connectFailure", "pendingAcquireTimeout", "fdOrEphemeralPortError", "cpuMemory"],
  preregisteredDecisionStates: ["ADOPT", "NOT_EFFECTIVE", "RELIABILITY_IMPROVED_BUT_TOO_COSTLY", "BASELINE_NOT_REPRODUCED", "INVALID", "NOT_RUN"],
  comparisonMetrics: [
    "successfulRps",
    "acceptedP95Ms",
    "acceptedP99Ms",
    "controlled503",
    "timeout",
    "unfinishedBacklog",
    "transportFailure",
    "poolActive",
    "poolPending",
    "connectionLifecycleEvidence",
    "cpu",
    "memory",
    "dbState",
  ],
  decisionState: "NOT_RUN",
  forbiddenAtPreflight: ["core performance result", "policy effectiveness decision", "aggregate outcome"],
}

if (process.argv[2] === "--readiness") {
  const [, , , coreRoot, outputPath] = process.argv
  const runs = ["BASELINE-001", "REMEDIATION-001", "BASELINE-002", "REMEDIATION-002", "BASELINE-003", "REMEDIATION-003"]
  const required = schema.requiredArtifactsPerRun
  const result = {
    executionStatus: "NOT_RUN",
    requiredRuns: runs,
    completedRuns: [],
    missingRuns: runs,
    requiredArtifacts: required,
    aggregateReadiness: "INCOMPLETE",
    decisionState: "NOT_RUN",
  }
  if (fs.existsSync(coreRoot)) {
    for (const run of runs) {
      const directory = path.join(coreRoot, `RUN-20260803-EXP119-${run}`)
      if (fs.existsSync(directory)) {
        const complete = required.every((item) => fs.existsSync(path.join(directory, item)))
        if (complete) result.completedRuns.push(run)
      }
    }
    result.missingRuns = runs.filter((run) => !result.completedRuns.includes(run))
    if (result.completedRuns.length === runs.length) result.aggregateReadiness = "READY_TO_AGGREGATE"
  }
  fs.mkdirSync(path.dirname(outputPath), { recursive: true })
  fs.writeFileSync(outputPath, `${JSON.stringify(result, null, 2)}\n`)
  process.exit(0)
}

const outputPath = process.argv[2]

fs.mkdirSync(path.dirname(outputPath), { recursive: true })
fs.writeFileSync(outputPath, `${JSON.stringify(schema, null, 2)}\n`)
