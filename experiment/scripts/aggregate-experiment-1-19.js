#!/usr/bin/env node

// Schema-only preparation for Experiment 1-19.  This does not read, create,
// or aggregate core performance results.  Core execution is intentionally
// outside the preflight task.

const fs = require("fs")
const path = require("path")

if (process.argv.length !== 3) {
  throw new Error("Usage: node aggregate-experiment-1-19.js <schema-output.json>")
}

const outputPath = process.argv[2]
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

fs.mkdirSync(path.dirname(outputPath), { recursive: true })
fs.writeFileSync(outputPath, `${JSON.stringify(schema, null, 2)}\n`)
