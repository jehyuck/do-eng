const fs = require('fs');
const path = require('path');
const root = path.resolve(process.argv[2]);
const errors = [];
const required = [
  'rendered-compose.yaml', 'runtime-container-environment.json',
  'application-resolved-config.json', 'admission-metrics-before.json',
  'admission-metrics-during.json', 'admission-metrics-after.json',
  'pool-provider-identity.json', 'pool-series-mapping.json',
  'exp131-run-config.json', 'lifecycle-timeline.json',
  'pool/pool-metrics.jsonl', 'pool/collector-failures.jsonl',
  'pool/pool-metrics.jsonl.summary.json'
];
const read = f => JSON.parse(fs.readFileSync(path.join(root, f), 'utf8').replace(/^\uFEFF/, ''));
for (const f of required) if (!fs.existsSync(path.join(root, f))) errors.push(`missing:${f}`);
let cfg, env, resolved, identity, mapping;
try { cfg = read('exp131-run-config.json'); env = read('runtime-container-environment.json'); resolved = read('application-resolved-config.json'); identity = read('pool-provider-identity.json'); mapping = read('pool-series-mapping.json'); } catch (e) { errors.push(`json:${e.message}`); }
if (cfg && (cfg.admissionMode !== 'OFF' || cfg.admissionEnabled !== false)) errors.push('config admission not OFF');
if (env) { const text = (env.variables || []).join('\n'); if (!/DOENG_ADMISSION_MODE=OFF/.test(text)) errors.push('runtime mode unavailable/not OFF'); if (!/DOENG_AI_ADMISSION_ENABLED=false/.test(text)) errors.push('runtime enabled unavailable/not false'); }
for (const phase of ['admissionBefore', 'admissionDuring', 'admissionAfter']) {
  const x = resolved && (resolved[phase] || resolved.resolved);
  if (!x) { errors.push(`resolved missing:${phase}`); continue; }
  const a = x.admission || x;
  if (x.mode !== 'OFF' || a.enabled !== false) errors.push(`resolved not OFF:${phase}`);
  for (const key of ['started', 'completed', 'rejected', 'currentInUse', 'released', 'cancelled']) if (Number(a[key]) !== 0) errors.push(`admission nonzero:${phase}.${key}`);
}
if (!identity || !Array.isArray(identity.profiles) || identity.profiles.length !== 4) errors.push('identity profiles incomplete');
if (!mapping || mapping.conclusion !== 'METER_SERIES_EXPOSED' || !Array.isArray(mapping.series) || mapping.series.length === 0) errors.push('pool series not exposed');
if (fs.existsSync(path.join(root, 'pool/pool-metrics.jsonl.summary.json'))) { const s = read('pool/pool-metrics.jsonl.summary.json'); if (Number(s.failures) !== 0) errors.push(`collector failures:${s.failures}`); }
if (errors.length) { console.error(JSON.stringify({ experiment: 'Exp131', artifactValidation: 'FAILED', errors }, null, 2)); process.exit(1); }
console.log(JSON.stringify({ experiment: 'Exp131', artifactValidation: 'PASSED', artifactRoot: root }, null, 2));
