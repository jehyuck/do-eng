const fs=require('fs'),path=require('path');
if(process.argv.length!==6||process.argv[2]!=='--readiness')throw Error('usage');
const date=process.argv[3],root=path.resolve(process.argv[4]),out=process.argv[5];
const arms=['BASELINE-001','REMEDIATION-001','BASELINE-002','REMEDIATION-002','BASELINE-003','REMEDIATION-003'];
const valid=[],reasons={};
for(const arm of arms){const id=`RUN-${date}-EXP126-${arm}`,dir=path.join(root,id);try{const s=JSON.parse(fs.readFileSync(path.join(dir,'execution-summary.json'),'utf8'));if(s.executionStatus!=='COMPLETED'||s.artifactValidation!=='PASSED')throw Error('execution summary');if(fs.existsSync(path.join(dir,'RUNNING'))||fs.existsSync(path.join(dir,'EXECUTION_FAILED')))throw Error('terminal exclusivity');valid.push(arm)}catch(e){reasons[arm]=e.message}}
fs.mkdirSync(path.dirname(out),{recursive:true});fs.writeFileSync(out,JSON.stringify({experiment:'Experiment 1-26',runDate:date,completedRuns:valid,missingRuns:arms.filter(x=>!valid.includes(x)),reasons,aggregateReadiness:valid.length===6?'READY_TO_AGGREGATE':'INCOMPLETE',decisionState:'NOT_RUN'},null,2)+'\n');
