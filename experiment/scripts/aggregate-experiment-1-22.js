const fs = require('fs');
const path = require('path');

if (process.argv.length !== 6 || process.argv[2] !== '--readiness') {
  throw new Error('Usage: node aggregate-experiment-1-22.js --readiness <runDate> <coreRoot> <output>');
}

const [, , , date, root, out] = process.argv;
const runs = ['BASELINE-001', 'REMEDIATION-001', 'BASELINE-002', 'REMEDIATION-002', 'BASELINE-003', 'REMEDIATION-003'];
const required = [
  'run-config.json', 'client-results.json', 'client-progress.jsonl',
  'pool/pool-metrics.jsonl', 'pool/pool-metrics.jsonl.summary.json', 'pool/collector-coverage.json',
  'application/container-stop.json', 'application/docker-logs.stdout.log', 'application/docker-logs.stderr.log',
  'application/docker-logs-capture.json', 'application/application.log', 'database/database-metrics.jsonl',
  'container/container-stats.jsonl', 'mock/load-stop-mock-metrics.json', 'drain/mock-drain-summary.json',
  'verification-summary.json', 'provenance/runtime-provenance.json', 'provenance/execution-timeline.json',
  'execution-summary.json'
];

function json(file) { return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '')); }
function timestamp(value) {
  const parsed = Date.parse(value || '');
  if (Number.isNaN(parsed)) throw new Error('invalid timestamp');
  return parsed;
}

const completed = [];
for (const run of runs) {
  const dir = path.join(root, `RUN-${date}-EXP122-${run}`);
  try {
    const summary = json(path.join(dir, 'execution-summary.json'));
    const config = json(path.join(dir, 'run-config.json'));
    const lines = fs.readFileSync(path.join(dir, 'pool/pool-metrics.jsonl'), 'utf8').split(/\r?\n/).filter(Boolean);
    const poolSummary = json(path.join(dir, 'pool/pool-metrics.jsonl.summary.json'));
    const coverage = json(path.join(dir, 'pool/collector-coverage.json'));
    const stop = json(path.join(dir, 'application/container-stop.json'));
    const capture = json(path.join(dir, 'application/docker-logs-capture.json'));
    const timeline = json(path.join(dir, 'provenance/execution-timeline.json'));
    const appDir = path.resolve(path.join(dir, 'application'));
    const appPrefix = appDir + path.sep;
    const capturePaths = [capture.stdoutPath, capture.stderrPath, capture.combinedPath];
    const pathsLocal = capturePaths.every(value => path.resolve(value).startsWith(appPrefix));
    const bytesMatch = capturePaths.map(value => fs.statSync(value).size);
    const timelineKeys = [
      'collectorProcessStartedAt', 'collectorFirstValidSampleAt', 'coreInvocationStartedAt',
      'coreInvocationCompletedAt', 'collectorProcessCompletedAt', 'applicationStopStartedAt',
      'applicationStopCompletedAt', 'applicationLogCaptureStartedAt', 'applicationLogCaptureCompletedAt',
      'artifactValidationCompletedAt', 'finalizationCompletedAt'
    ];
    const ordered = timelineKeys.map(key => timestamp(timeline[key]));
    const timelineOrdered = ordered.every((value, index) => index === 0 || value >= ordered[index - 1]);
    const stopContract = stop.runId === config.runId
      && typeof stop.containerId === 'string' && stop.containerId.length > 0
      && typeof stop.command === 'string' && stop.command.length > 0
      && stop.gracePeriodSeconds === 15 && stop.processTimeoutSeconds === 30
      && stop.timedOut === false && stop.exitCode === 0
      && stop.stateBefore === 'running' && ['exited', 'stopped'].includes(stop.stateAfter)
      && stop.containerStillExists === true
      && stop.inspectExitCodeBefore === 0 && stop.inspectExitCodeAfter === 0
      && stop.stopStatus === 'APPLICATION_CONTAINER_STOPPED';
    const captureContract = capture.runId === config.runId
      && capture.containerId === stop.containerId
      && capture.captureMode === 'POST_STOP_SNAPSHOT'
      && capture.timedOut === false
      && capture.captureStatus === 'APPLICATION_LOG_CAPTURE_PASSED'
      && capture.exitCode === 0;
    const timelineContract = timeline.applicationStopStartedAt === stop.startedAt
      && timeline.applicationStopCompletedAt === stop.completedAt
      && timeline.applicationLogCaptureStartedAt === capture.startedAt
      && timeline.applicationLogCaptureCompletedAt === capture.completedAt;
    if (
      fs.existsSync(path.join(dir, 'COMPLETED')) && !fs.existsSync(path.join(dir, 'EXECUTION_FAILED'))
      && required.every(file => fs.existsSync(path.join(dir, file)))
      && summary.executionStatus === 'COMPLETED' && summary.artifactValidation === 'PASSED'
      && lines.length > 1 && lines.every(line => JSON.parse(line))
      && poolSummary.failures === 0
      && coverage.coverageStatus === 'COLLECTOR_COVERAGE_PASSED'
      && coverage.coversCoreStart && coverage.coversCoreEnd
      && coverage.timestampsNonDecreasing && coverage.invalidSampleCount === 0 && coverage.collectorFailures === 0
      && stopContract && captureContract && timelineContract
      && (capture.stdoutBytes + capture.stderrBytes) > 0
      && capture.stdoutBytes === bytesMatch[0] && capture.stderrBytes === bytesMatch[1]
      && capture.combinedBytes === bytesMatch[2] && pathsLocal && timelineOrdered
    ) completed.push(run);
  } catch (_) { /* incomplete run remains in missingRuns */ }
}

const result = {
  experiment: 'Experiment 1-22',
  runDate: date,
  completedRuns: completed,
  missingRuns: runs.filter(run => !completed.includes(run)),
  aggregateReadiness: completed.length === 6 ? 'READY_TO_AGGREGATE' : 'INCOMPLETE',
  decisionState: 'NOT_RUN'
};
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, `${JSON.stringify(result, null, 2)}\n`);
