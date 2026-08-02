const fs = require("fs")

const baselinePath = process.argv[2]
const remediationPath = process.argv[3]
const outputPath = process.argv[4]
if (!baselinePath || !remediationPath || !outputPath) {
  throw new Error("baseline, remediation, and output paths are required")
}

const baseline = JSON.parse(fs.readFileSync(baselinePath, "utf8").replace(/^\uFEFF/, ""))
const remediation = JSON.parse(fs.readFileSync(remediationPath, "utf8").replace(/^\uFEFF/, ""))
const key = "DOENG_EXTERNAL_MAX_IDLE_TIME_MS"
const baselineValue = String(baseline.services["flux-corrected"].environment[key])
const remediationValue = String(remediation.services["flux-corrected"].environment[key])
remediation.services["flux-corrected"].environment[key] = baseline.services["flux-corrected"].environment[key]
const otherwiseIdentical = JSON.stringify(baseline) === JSON.stringify(remediation)
const result = {
  generatedAt: new Date().toISOString(),
  baselineClientMaxIdleTimeMs: Number(baselineValue),
  remediationClientMaxIdleTimeMs: Number(remediationValue),
  allowedDifference: key,
  otherwiseIdentical,
  valid: baselineValue === "0" && remediationValue === "4000" && otherwiseIdentical,
}
fs.writeFileSync(outputPath, `${JSON.stringify(result, null, 2)}\n`)
process.stdout.write(`${JSON.stringify(result)}\n`)
if (!result.valid) process.exitCode = 1
