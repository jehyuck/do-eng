const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
if (process.argv.length !== 6 || process.argv[2] !== '--readiness') throw new Error('usage');
const date = process.argv[3];
const root = path.resolve(process.argv[4]);
const out = process.argv[5];
const arms = ['BASELINE-001','REMEDIATION-001','BASELINE-002','REMEDIATION-002','BASELINE-003','REMEDIATION-003'];
const required = ['run-config.json','client-results.json','client-progress.jsonl','pool/pool-metrics.jsonl','pool/pool-metrics.jsonl.summary.json','pool/collector-coverage.json','pool/collector-lifecycle.json','application/container-stop.json','application/docker-logs.stdout.log','application/docker-logs.stderr.log','application/docker-logs-capture.json','application/application.log','database/database-metrics.jsonl','container/container-stats.jsonl','mock/load-stop-mock-metrics.json','drain/mock-drain-summary.json','verification-summary.json','provenance/runtime-provenance.json','provenance/execution-timeline.json','execution-summary.json'];
const time = value => { const n = Date.parse(value || ''); if (Number.isNaN(n)) throw Error('invalid timestamp'); return n; };
const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const valid = [], reasons = {};
for (const arm of arms) {
  const dir = path.join(root, `RUN-${date}-EXP123-${arm}`);
  try {
    for (const rel of required) if (!fs.existsSync(path.join(dir, rel))) throw Error(`missing ${rel}`);
    if (!fs.existsSync(path.join(dir, 'COMPLETED')) || fs.existsSync(path.join(dir, 'EXECUTION_FAILED'))) throw Error('terminal marker');
    const r=read(path.join(dir,'run-config.json')), s=read(path.join(dir,'execution-summary.json')), l=read(path.join(dir,'pool/collector-lifecycle.json')), c=read(path.join(dir,'pool/collector-coverage.json')), p=read(path.join(dir,'provenance/runtime-provenance.json')), tl=read(path.join(dir,'provenance/execution-timeline.json')), stop=read(path.join(dir,'application/container-stop.json')), cap=read(path.join(dir,'application/docker-logs-capture.json'));
    const keys=['collectorProcessStartedAt','collectorFirstValidSampleAt','coreInvocationStartedAt','coreInvocationCompletedAt','collectorFirstSampleCoveringCoreEndAt','postCoreCoverageConfirmedAt','collectorStopSignalIssuedAt','collectorProcessCompletedAt','applicationStopStartedAt','applicationStopCompletedAt','applicationLogCaptureStartedAt','applicationLogCaptureCompletedAt','artifactValidationCompletedAt','finalizationCompletedAt']; const times=keys.map(k=>time(tl[k])); if(times.some((v,i)=>i&&v<times[i-1])) throw Error('timeline order');
    if(tl.applicationStopStartedAt!==stop.startedAt||tl.applicationStopCompletedAt!==stop.completedAt||tl.applicationLogCaptureStartedAt!==cap.startedAt||tl.applicationLogCaptureCompletedAt!==cap.completedAt) throw Error('timeline identity');
    const samples=fs.readFileSync(path.join(dir,'pool/pool-metrics.jsonl'),'utf8').split(/\r?\n/).filter(Boolean).map(JSON.parse); const first=samples.find(x=>(x.failure==null||x.failure==='')&&time(x.timestamp)>=time(c.coreInvocationCompletedAt)); if(!first||first.timestamp!==c.waitReturnedFirstCoveringSampleAt||first.timestamp!==c.collectorFirstSampleCoveringCoreEndAt||first.timestamp!==l.collectorFirstSampleCoveringCoreEndAt||first.timestamp!==tl.collectorFirstSampleCoveringCoreEndAt) throw Error('first-covering identity');
    if(l.summaryCollectorStatus!=='COLLECTOR_STOPPED_BY_SIGNAL'||l.summaryStopSignalObserved!==true||l.summaryFailures!==0||l.lifecycleStatus!=='COLLECTOR_LIFECYCLE_PASSED'||l.failureType!==null||l.processExitCode!==0) throw Error('collector lifecycle');
    if(s.executionStatus!=='COMPLETED'||s.artifactValidation!=='PASSED'||s.cleanupResult!=='COMPLETED') throw Error('summary');
    if(p.runtimeProvenance!=='ACTUAL'||p.runId!==r.runId||p.runDate!==r.runDate||p.condition!==r.condition||p.applicationImageTag!==r.applicationImageTag||p.applicationImageId!==r.applicationImageId||p.mockImageTag!==r.mockImageTag||p.mockImageId!==r.mockImageId||p.collectorMode!=='CORE_BOUND_STOP_SIGNAL'||p.composeFiles.length!==7||r.composeFiles.length!==7) throw Error('provenance');
    for(const f of r.composeFiles){const q=p.composeFiles.find(x=>String(x.path)===String(f.path));if(!q||q.sha256!==f.sha256)throw Error('compose identity');const abs=path.resolve(__dirname,'..','..',f.path);const actual=crypto.createHash('sha256').update(fs.readFileSync(abs)).digest('hex');if(actual!==f.sha256)throw Error('compose actual hash');}
    if(stop.runId!==r.runId||!stop.containerId||!stop.command||stop.gracePeriodSeconds!==15||stop.processTimeoutSeconds!==30||stop.timedOut!==false||stop.exitCode!==0||stop.stateBefore!=='running'||!['exited','stopped'].includes(stop.stateAfter)||stop.containerStillExists!==true||stop.inspectExitCodeBefore!==0||stop.inspectExitCodeAfter!==0||stop.stopStatus!=='APPLICATION_CONTAINER_STOPPED')throw Error('stop contract');
    if(cap.runId!==r.runId||cap.containerId!==stop.containerId||cap.captureMode!=='POST_STOP_SNAPSHOT'||!['exited','stopped'].includes(cap.containerStateAtCapture)||cap.timeoutSeconds!==30||cap.timedOut!==false||cap.exitCode!==0||cap.captureStatus!=='APPLICATION_LOG_CAPTURE_PASSED')throw Error('capture contract');
    const appDir=path.resolve(dir,'application'); const paths={stdoutPath:'docker-logs.stdout.log',stderrPath:'docker-logs.stderr.log',combinedPath:'application.log'}; for(const [key,name] of Object.entries(paths)){const candidate=path.resolve(cap[key]);const rel=path.relative(appDir,candidate);if(path.isAbsolute(rel)||rel==='..'||rel.startsWith(`..${path.sep}`)||candidate!==path.join(appDir,name))throw Error('capture path');} if(Number(cap.stdoutBytes)!==fs.statSync(cap.stdoutPath).size||Number(cap.stderrBytes)!==fs.statSync(cap.stderrPath).size||Number(cap.combinedBytes)!==fs.statSync(cap.combinedPath).size||cap.stdoutBytes+cap.stderrBytes<=0||cap.combinedBytes<=0)throw Error('capture bytes');
    valid.push(arm);
  } catch (error) { reasons[arm]=error.message; }
}
fs.mkdirSync(path.dirname(out), {recursive:true}); fs.writeFileSync(out, JSON.stringify({experiment:'Experiment 1-23',runDate:date,completedRuns:valid,missingRuns:arms.filter(x=>!valid.includes(x)),reasons,aggregateReadiness:valid.length===6?'READY_TO_AGGREGATE':'INCOMPLETE',decisionState:'NOT_RUN'}, null, 2)+'\n');
